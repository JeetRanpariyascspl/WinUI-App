<#
.SYNOPSIS
    Helper used by the WinUI-App Inno Setup installer to deploy and remove the MSIX package.

.NOTES
    Exit codes:   0 = success
                  1 = failure (details are in the log file)
                  3 = a newer version of the package is already installed
                  4 = dependency / framework packages missing or conflicting
                  5 = the signing certificate is not trusted
                  6 = installing apps outside the Store (sideloading) is disabled
                  7 = same identity but a different signature is already installed
                  8 = the .msix identity differs from the one Setup was built for
                 20 = (Detect only) the package is not installed
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Detect', 'Install', 'Update', 'Reinstall', 'Shortcuts', 'Uninstall')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$PackageName,

    [string]$AppDir,
    [string]$PackageFile,
    [string]$CertificateFile,
    [string]$IconFile,
    [string]$LogFile,
    [string]$InfoFile,
    [string]$UninstallExe,
    [string]$UninstallRegKey,
    [string]$ExpectedVersion,
    [string]$ShortcutName = 'WinUI-App',
    [switch]$DesktopShortcut,
    [switch]$StartMenuShortcut
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    if (-not $LogFile) { return }
    try {
        $dir = Split-Path -Parent $LogFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $line = '{0}  [{1}]  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
    catch { }
}

# ---------------------------------------------------------------------------
# Diagnostics (so a failure on any PC can be understood from installation.log)
# ---------------------------------------------------------------------------
function Write-Diagnostics {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        Write-Log ('OS: {0} (build {1}), PowerShell {2}' -f $os.Caption, $os.BuildNumber, $PSVersionTable.PSVersion)
    }
    catch { }

    foreach ($key in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx',
                       'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock')) {
        try {
            if (Test-Path -LiteralPath $key) {
                $props = (Get-ItemProperty -LiteralPath $key).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }
                foreach ($prop in $props) { Write-Log ('{0}  {1} = {2}' -f $key, $prop.Name, $prop.Value) }
            }
        }
        catch { }
    }
}

function Write-ErrorDetails {
    param([string]$Message)
    # Windows puts an ActivityId in deployment errors; Get-AppPackageLog turns it into the real reason.
    if ($Message -match '(?i)ActivityId\]?\s+([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})') {
        $activity = $Matches[1]
        try {
            $details = Get-AppPackageLog -ActivityID $activity -ErrorAction Stop | Out-String
            Write-Log ("Deployment log for activity {0}:`r`n{1}" -f $activity, $details) 'ERROR'
        }
        catch {
            Write-Log "Could not read the deployment log for activity $activity." 'WARN'
        }
    }
}

function Get-ExitCodeForError {
    param([string]$Message)
    switch -Regex ($Message) {
        '0x80073D06'                  { return 3 }
        '0x80073CF3'                  { return 4 }
        '0x800B0109|0x800B010A'       { return 5 }
        '0x80073CFF'                  { return 6 }
        '0x80073CFB'                  { return 7 }
        'does not match the identity' { return 8 }
        default                       { return 1 }
    }
}

# ---------------------------------------------------------------------------
# Package helpers
# ---------------------------------------------------------------------------
function Get-PackageManifestInfo {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
        if (-not $entry) { return $null }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $identity = ([xml]$text).Package.Identity
        return [pscustomobject]@{
            Name      = [string]$identity.Name
            Version   = [string]$identity.Version
            Publisher = [string]$identity.Publisher
        }
    }
    finally { $zip.Dispose() }
}
function Get-InstalledPackages {
    @(Get-AppxPackage -Name $PackageName)
}

function Get-AppUserModelId {
    $pkg = Get-InstalledPackages | Select-Object -First 1
    if (-not $pkg) { throw "Package '$PackageName' is not installed." }

    $appId = 'App'
    try {
        $manifest = Get-AppxPackageManifest -Package $pkg.PackageFullName
        $first = @($manifest.Package.Applications.Application)[0]
        if ($first -and $first.Id) { $appId = [string]$first.Id }
    }
    catch {
        Write-Log "Could not read the package manifest, assuming Application Id 'App': $($_.Exception.Message)" 'WARN'
    }
    return ('{0}!{1}' -f $pkg.PackageFamilyName, $appId)
}

function Remove-InstalledPackage {
    $pkgs = Get-InstalledPackages
    if ($pkgs.Count -eq 0) {
        Write-Log 'No existing package found - nothing to remove.'
        return
    }
    foreach ($p in $pkgs) {
        Write-Log "Removing package: $($p.PackageFullName)"
        Remove-AppxPackage -Package $p.PackageFullName
    }
}

function Invoke-Deploy {
    if (-not $PackageFile -or -not (Test-Path -LiteralPath $PackageFile)) {
        throw "Package file not found: $PackageFile"
    }

    $info = $null
    try { $info = Get-PackageManifestInfo -Path $PackageFile }
    catch { Write-Log "Could not read the package manifest: $($_.Exception.Message)" 'WARN' }

    if ($info) {
        Write-Log ('Package identity: {0}   version {1}   publisher {2}' -f $info.Name, $info.Version, $info.Publisher)
        if ($info.Name -ne $PackageName) {
            throw "The package identity '$($info.Name)' does not match the identity Setup was built for ('$PackageName'). Rebuild Setup with the matching PackageIdentityName."
        }
        if ($ExpectedVersion -and ($info.Version -ne $ExpectedVersion)) {
            Write-Log "Setup is labelled $ExpectedVersion but the package inside it is version $($info.Version)." 'WARN'
        }
    }

    if ($CertificateFile -and (Test-Path -LiteralPath $CertificateFile)) {
        Write-Log "Trusting package certificate: $CertificateFile"
        Import-Certificate -FilePath $CertificateFile -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    }
    else {
        Write-Log 'No certificate file found - skipping the certificate trust step.' 'WARN'
    }

    $deps = @()
    $depDir = Join-Path $AppDir 'Dependencies\x64'
    if (Test-Path -LiteralPath $depDir) {
        $deps = @(Get-ChildItem -LiteralPath $depDir -Filter '*.appx' | Select-Object -ExpandProperty FullName)
    }
    Write-Log ('Dependency packages found: {0}' -f $deps.Count)
    if ($deps.Count -eq 0) {
        Write-Log 'No dependency packages were bundled. This only works if the PC already has the required framework packages (for example the Windows App Runtime).' 'WARN'
    }

    $params = @{ Path = $PackageFile; ForceApplicationShutdown = $true }
    if ($deps.Count -gt 0) { $params['DependencyPath'] = $deps }

    Write-Log "Installing package: $PackageFile"
    Add-AppxPackage @params
    Write-Log 'Add-AppxPackage finished.'

    # Do not trust "no error": make sure Windows really has the version we just deployed.
    $installed = Get-InstalledPackages | Select-Object -First 1
    if (-not $installed) { throw 'Windows reported success, but the package is not installed.' }
    Write-Log "Installed package version is now $($installed.Version)."
    if ($info -and ([version][string]$installed.Version -ne [version]$info.Version)) {
        throw "Windows still has version $($installed.Version) instead of $($info.Version)."
    }

    if ($InfoFile) {
        # The installer reads this to implement the "Open App" button.
        Set-Content -LiteralPath $InfoFile -Value (Get-AppUserModelId) -Encoding ASCII
    }
}

# ---------------------------------------------------------------------------
# Shortcuts
# ---------------------------------------------------------------------------
function Get-ShortcutPaths {
    [pscustomobject]@{
        Desktop   = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) "$ShortcutName.lnk"
        StartMenu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) "$ShortcutName.lnk"
    }
}

function New-AppShortcuts {
    $aumid = Get-AppUserModelId
    $paths = Get-ShortcutPaths
    $shell = New-Object -ComObject WScript.Shell

    $targets = @()
    if ($DesktopShortcut)   { $targets += $paths.Desktop }
    if ($StartMenuShortcut) { $targets += $paths.StartMenu }

    foreach ($path in $targets) {
        Write-Log "Creating shortcut: $path"
        $lnk = $shell.CreateShortcut($path)
        $lnk.TargetPath  = Join-Path $env:WINDIR 'explorer.exe'
        $lnk.Arguments   = "shell:AppsFolder\$aumid"
        $lnk.Description = $ShortcutName
        if ($IconFile -and (Test-Path -LiteralPath $IconFile)) {
            $lnk.IconLocation = "$IconFile,0"
        }
        $lnk.Save()
    }
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
function Invoke-Uninstall {
    # 1) Let the installer's own uninstaller clean up its files/registry entry (it also removes the package).
    if ($UninstallExe -and (Test-Path -LiteralPath $UninstallExe)) {
        Write-Log "Running the registered uninstaller: $UninstallExe"
        Start-Process -FilePath $UninstallExe -ArgumentList '/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES' -Wait

        # The uninstaller hands over to a temporary copy of itself, so wait until unins000.exe is really gone.
        $deadline = (Get-Date).AddSeconds(120)
        while ((Test-Path -LiteralPath $UninstallExe) -and ((Get-Date) -lt $deadline)) {
            Start-Sleep -Milliseconds 300
        }
        if (Test-Path -LiteralPath $UninstallExe) {
            Write-Log 'The uninstaller did not finish within 120 seconds.' 'WARN'
        }
    }
    else {
        Write-Log 'No registered uninstaller found - removing the package directly.'
    }

    # 2) Make sure the MSIX package is gone no matter what.
    Remove-InstalledPackage

    # 3) Shortcuts.
    $paths = Get-ShortcutPaths
    foreach ($path in @($paths.Desktop, $paths.StartMenu)) {
        if (Test-Path -LiteralPath $path) {
            Write-Log "Removing shortcut: $path"
            Remove-Item -LiteralPath $path -Force
        }
    }

    # 4) Stale "Apps & features" entry (only left behind if the uninstaller could not run).
    if ($UninstallRegKey) {
        $key = "HKLM:\$UninstallRegKey"
        if (Test-Path -LiteralPath $key) {
            Write-Log "Removing leftover uninstall entry: $key"
            Remove-Item -LiteralPath $key -Recurse -Force
        }
    }

    if ((Get-InstalledPackages).Count -gt 0) {
        throw 'The app package is still installed.'
    }
    Write-Log 'Uninstall completed.'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$exitCode = 0
try {
    if ($Action -ne 'Detect') {
        Write-Log ('===== {0} started =====' -f $Action)
        if (@('Install', 'Update', 'Reinstall') -contains $Action) { Write-Diagnostics }
    }

    switch ($Action) {
        'Detect' {
            $pkg = Get-InstalledPackages | Select-Object -First 1
            if ($pkg) {
                if ($InfoFile) { Set-Content -LiteralPath $InfoFile -Value ([string]$pkg.Version) -Encoding ASCII }
                $exitCode = 0
            }
            else {
                $exitCode = 20
            }
        }
        'Install'   { Invoke-Deploy }
        'Update'    { Invoke-Deploy }
        'Reinstall' { Remove-InstalledPackage; Invoke-Deploy }
        'Shortcuts' { New-AppShortcuts }
        'Uninstall' { Invoke-Uninstall }
    }

    if ($Action -ne 'Detect') {
        Write-Log ('===== {0} finished =====' -f $Action)
    }
}
catch {
    $message = $_.Exception.Message
    Write-Log $message 'ERROR'
    Write-ErrorDetails -Message $message
    $exitCode = Get-ExitCodeForError -Message $message
    Write-Log "Exit code: $exitCode" 'ERROR'
}

exit $exitCode
