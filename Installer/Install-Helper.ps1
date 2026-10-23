<#
.SYNOPSIS
    Helper used by the WinUI-App Inno Setup installer to deploy and remove the MSIX package.

.NOTES
    Exit codes:   0 = success
                  1 = failure (details are in the log file)
                  3 = a newer version of the package is already installed
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
# Package helpers
# ---------------------------------------------------------------------------
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

function Test-DotNetRuntimeInstalled {
    $runtimeDir = Join-Path $env:ProgramFiles 'dotnet\shared\Microsoft.NETCore.App'
    if (-not (Test-Path -LiteralPath $runtimeDir)) { return $false }

    foreach ($directory in Get-ChildItem -LiteralPath $runtimeDir -Directory) {
        $version = $null
        if ([Version]::TryParse($directory.Name, [ref]$version) -and $version -ge [Version]'10.0.0') {
            return $true
        }
    }
    return $false
}

function Invoke-DownloadAndInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $installerPath = Join-Path $env:TEMP ('WinUI-App-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        Write-Log "Downloading $Description from $Uri"
        Invoke-WebRequest -Uri $Uri -OutFile $installerPath -UseBasicParsing
        if (-not (Test-Path -LiteralPath $installerPath) -or (Get-Item -LiteralPath $installerPath).Length -eq 0) {
            throw "The $Description download was empty."
        }

        Write-Log "Installing $Description"
        $process = Start-Process -FilePath $installerPath -ArgumentList $Arguments -Wait -PassThru
        if ($process.ExitCode -notin 0, 3010) {
            throw "$Description installer failed with exit code $($process.ExitCode)."
        }
        if ($process.ExitCode -eq 3010) {
            Write-Log "$Description installed successfully; a restart may be required." 'WARN'
        }
    }
    finally {
        if (Test-Path -LiteralPath $installerPath) {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Ensure-DeploymentRuntimes {
    if (-not (Test-DotNetRuntimeInstalled)) {
        Invoke-DownloadAndInstall `
            -Uri 'https://aka.ms/dotnet/10.0/dotnet-runtime-win-x64.exe' `
            -Arguments '/install /quiet /norestart' `
            -Description '.NET 10 x64 runtime'

        if (-not (Test-DotNetRuntimeInstalled)) {
            throw 'The .NET 10 runtime installer completed, but the runtime was not found.'
        }
    }
    else {
        Write-Log '.NET 10 runtime is already installed.'
    }

    $installedWindowsAppRuntimes = @(Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsAppRuntime.2' |
        Where-Object { $_.Version -ge [Version]'2.5.1.0' })
    if ($installedWindowsAppRuntimes.Count -eq 0) {
        Invoke-DownloadAndInstall `
            -Uri 'https://aka.ms/windowsappsdk/2.5/2.5.1/windowsappruntimeinstall-x64.exe' `
            -Arguments '--quiet' `
            -Description 'Windows App Runtime 2.5.1 x64'

        $installedWindowsAppRuntimes = @(Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsAppRuntime.2' |
            Where-Object { $_.Version -ge [Version]'2.5.1.0' })
        if ($installedWindowsAppRuntimes.Count -eq 0) {
            throw 'The Windows App Runtime installer completed, but version 2.5.1 or later was not found.'
        }
    }
    else {
        Write-Log 'Windows App Runtime 2.5.1 or later is already installed.'
    }
}

function Invoke-Deploy {
    if (-not $PackageFile -or -not (Test-Path -LiteralPath $PackageFile)) {
        throw "Package file not found: $PackageFile"
    }

    Ensure-DeploymentRuntimes

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
        $deps = @(Get-ChildItem -LiteralPath $depDir -File |
            Where-Object { $_.Extension -in '.appx', '.msix' } |
            Select-Object -ExpandProperty FullName)
    }
    Write-Log ('Dependency packages found: {0}' -f $deps.Count)

    $params = @{ Path = $PackageFile; ForceApplicationShutdown = $true }
    if ($deps.Count -gt 0) { $params['DependencyPath'] = $deps }

    Write-Log "Installing package: $PackageFile"
    Add-AppxPackage @params
    Write-Log 'Package installed successfully.'

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

    if ($message -match '0x80073D06') {
        Write-Log 'A newer version of this package is already installed. Use Reinstall to replace it.' 'ERROR'
        $exitCode = 3
    }
    else {
        $exitCode = 1
    }
}

exit $exitCode
