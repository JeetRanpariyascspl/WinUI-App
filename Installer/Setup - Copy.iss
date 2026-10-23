#define AppName "WinUI-App"
#define AppVersion "1.0.0"
#define PublisherName "Jeet"
#define PackageDir "..\AppPackages\WinUI-App_1.0.0.0_x64_Debug_Test"
#define PackageIdentityName "33e7ed00-847b-4866-a0c6-a5b99929000f"
#define PackageFile "WinUI-App_1.0.0.0_x64_Debug.msix"
#define CertificateFile "WinUI-App_1.0.0.0_x64_Debug.cer"
#define AppIdValue "33e7ed00-847b-4866-a0c6-a5b99929000f"
#define UninstallKeyValue "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{33e7ed00-847b-4866-a0c6-a5b99929000f}_is1"

[Setup]
AppId={{{#AppIdValue}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#PublisherName}
AppVerName={#AppName} {#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename={#AppName}_{#AppVersion}
SetupIconFile=..\WinUI-App\Image\WinUI-App.ico
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
VersionInfoVersion={#AppVersion}

[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\WinUI-App\Image\WinUI-App.ico"; DestDir: "{app}"; Flags: ignoreversion

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""$ErrorActionPreference = 'Stop'; Import-Certificate -FilePath '{app}\{#CertificateFile}' -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null; $deps = Get-ChildItem '{app}\Dependencies\x64\*.appx' | Select-Object -ExpandProperty FullName; Add-AppxPackage -Path '{app}\{#PackageFile}' -DependencyPath $deps -ForceApplicationShutdown *>&1 | Tee-Object -FilePath '{app}\installation.log'"""; \
    Description: "Install or update {#AppName}"; \
    Flags: waituntilterminated; \
    StatusMsg: "Installing {#AppName}..."
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""$p = Get-AppxPackage -Name '{#PackageIdentityName}'; $w = New-Object -ComObject WScript.Shell; $s = $w.CreateShortcut('{commondesktop}\{#AppName}.lnk'); $s.TargetPath = '{sys}\WindowsPowerShell\v1.0\powershell.exe'; $s.Arguments = '-NoProfile -WindowStyle Hidden -Command ""Invoke-Item ''''shell:AppsFolder\' + $p.PackageFamilyName + '!App''''""'; $s.IconLocation = '{app}\WinUI-App.ico,0'; $s.Save()"""; \
    Description: "Create desktop shortcut"; \
    Flags: runhidden waituntilterminated; \
    Tasks: desktopicon
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""$p = Get-AppxPackage -Name '{#PackageIdentityName}'; Invoke-Item ('shell:AppsFolder\' + $p.PackageFamilyName + '!App')"""; \
    Description: "Launch {#AppName}"; \
    Flags: postinstall nowait skipifsilent
Filename: "{app}"; \
    Description: "Open installation folder"; \
    Flags: postinstall shellexec skipifsilent unchecked
Filename: "{app}\installation.log"; \
    Description: "Open installation log"; \
    Flags: postinstall shellexec skipifsilent unchecked

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""$ErrorActionPreference = 'Stop'; $p = Get-AppxPackage -Name '{#PackageIdentityName}'; Remove-AppxPackage -Package $p.PackageFullName"""; \
    Flags: runhidden waituntilterminated

[UninstallDelete]
Type: files; Name: "{commondesktop}\{#AppName}.lnk"

[Code]
const
  UninstallKey = '{#UninstallKeyValue}';

var
  ExistingAppPage: TWizardPage;
  UpdateButton: TNewButton;
  UninstallButton: TNewButton;
  ExistingAppLabel: TNewStaticText;
  ExistingAppUninstalled: Boolean;

function IsPreviousInstallationPresent: Boolean;
var
  ResultCode: Integer;
begin
  Result := RegKeyExists(HKLM64, UninstallKey) or RegKeyExists(HKLM, UninstallKey);
  if not Result then
  begin
    Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -Command "$p = Get-AppxPackage -Name ''{#PackageIdentityName}''; exit [int]($null -eq $p)"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  end;
end;

function GetPreviousUninstaller(var UninstallerCommand: String): Boolean;
begin
  Result := RegQueryStringValue(HKLM64, UninstallKey, 'UninstallString', UninstallerCommand);
  if not Result then
    Result := RegQueryStringValue(HKLM, UninstallKey, 'UninstallString', UninstallerCommand);
end;

function SplitUninstallCommand(UninstallerCommand: String; var UninstallerPath,
  UninstallerParameters: String): Boolean;
var
  ClosingQuote: Integer;
  SpacePosition: Integer;
begin
  UninstallerCommand := Trim(UninstallerCommand);
  UninstallerPath := '';
  UninstallerParameters := '';

  if (Length(UninstallerCommand) > 0) and (UninstallerCommand[1] = '"') then
  begin
    ClosingQuote := 2;
    while (ClosingQuote <= Length(UninstallerCommand)) and
      (UninstallerCommand[ClosingQuote] <> '"') do
      ClosingQuote := ClosingQuote + 1;

    if ClosingQuote <= Length(UninstallerCommand) then
    begin
      UninstallerPath := Copy(UninstallerCommand, 2, ClosingQuote - 2);
      UninstallerParameters := Trim(Copy(UninstallerCommand, ClosingQuote + 1,
        Length(UninstallerCommand)));
    end;
  end
  else
  begin
    SpacePosition := Pos(' ', UninstallerCommand);
    if SpacePosition = 0 then
      UninstallerPath := UninstallerCommand
    else
    begin
      UninstallerPath := Copy(UninstallerCommand, 1, SpacePosition - 1);
      UninstallerParameters := Trim(Copy(UninstallerCommand, SpacePosition + 1,
        Length(UninstallerCommand)));
    end;
  end;

  Result := UninstallerPath <> '';
end;

procedure UpdateButtonClick(Sender: TObject);
begin
  WizardForm.NextButton.OnClick(WizardForm.NextButton);
end;

procedure UninstallButtonClick(Sender: TObject);
var
  ResultCode: Integer;
begin
  if Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = ''Stop''; $p = Get-AppxPackage -Name ''{#PackageIdentityName}''; Remove-AppxPackage -Package $p.PackageFullName"',
    '', SW_SHOW, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then
  begin
    ExistingAppUninstalled := True;
    WizardForm.CancelButton.OnClick(WizardForm.CancelButton);
  end
  else
    MsgBox('Windows could not uninstall the existing application.', mbError, MB_OK);
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if ExistingAppUninstalled then
  begin
    Cancel := True;
    Confirm := False;
  end;
end;

procedure InitializeWizard;
begin
  ExistingAppPage := CreateCustomPage(wpWelcome, 'Existing installation found',
    'Update or uninstall WinUI-App');

  ExistingAppLabel := TNewStaticText.Create(ExistingAppPage);
  ExistingAppLabel.Parent := ExistingAppPage.Surface;
  ExistingAppLabel.Left := ScaleX(0);
  ExistingAppLabel.Top := ScaleY(12);
  ExistingAppLabel.Width := ExistingAppPage.Surface.Width;
  ExistingAppLabel.Height := ScaleY(40);
  ExistingAppLabel.Caption := 'WinUI-App is already installed. Choose Update to install this version, or Uninstall to remove the current version.';
  ExistingAppLabel.WordWrap := True;

  UpdateButton := TNewButton.Create(ExistingAppPage);
  UpdateButton.Parent := ExistingAppPage.Surface;
  UpdateButton.Left := ScaleX(0);
  UpdateButton.Top := ScaleY(70);
  UpdateButton.Width := ScaleX(120);
  UpdateButton.Caption := 'Update';
  UpdateButton.OnClick := @UpdateButtonClick;

  UninstallButton := TNewButton.Create(ExistingAppPage);
  UninstallButton.Parent := ExistingAppPage.Surface;
  UninstallButton.Left := ScaleX(132);
  UninstallButton.Top := ScaleY(70);
  UninstallButton.Width := ScaleX(120);
  UninstallButton.Caption := 'Uninstall';
  UninstallButton.OnClick := @UninstallButtonClick;

  if IsPreviousInstallationPresent then
  begin
    WizardForm.WelcomeLabel1.Caption := 'Update ' + '{#AppName}';
    WizardForm.WelcomeLabel2.Caption :=
      'An existing installation was found. Click Next to update it.' + #13#10 + #13#10 +
      'To remove the application, use Uninstall in Windows Settings > Apps.';
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ExistingAppPage.ID) and not IsPreviousInstallationPresent;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'Publisher:' + NewLine + '  {#PublisherName}' + NewLine + NewLine +
    MemoDirInfo + NewLine + NewLine + MemoTasksInfo + NewLine + NewLine +
    'Installation log:' + NewLine + '  ' + ExpandConstant('{app}\installation.log');
end;
