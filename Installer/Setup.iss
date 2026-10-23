; ============================================================================
;  WinUI-App installer  (Inno Setup 6.x)  -  wraps a WinUI 3 MSIX package
;
;  Requires Install-Helper.ps1 next to this file (it is bundled into the EXE).
;
;  First install : Welcome -> choose folder -> choose shortcuts -> Ready ->
;                  Installing (big progress + step list) -> Finished
;                  with [Open App] and [Show Log] buttons.
;  Already there : "Update / Reinstall / Uninstall" page (no other pages are
;                  needed for Uninstall; Update and Reinstall go on to Ready,
;                  Installing and Finished).
; ============================================================================

#define AppName "WinUI-App"
#define AppVersion "1.0.0"
#define PublisherName "Jeet"
#define PackageDir "..\AppPackages\WinUI-App_1.0.0.0_x64_Test"
#define PackageIdentityName "33e7ed00-847b-4866-a0c6-a5b99929000f"
#define PackageFile "WinUI-App_1.0.0.0_x64.msix"
#define CertificateFile "WinUI-App_1.0.0.0_x64.cer"
#define AppIdValue "33e7ed00-847b-4866-a0c6-a5b99929000f"

[Setup]
AppId={{{#AppIdValue}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#PublisherName}
AppVerName={#AppName} {#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
UsePreviousAppDir=yes
OutputDir=Output
OutputBaseFilename={#AppName}_{#AppVersion}
SetupIconFile=..\WinUI-App\Image\WinUI-App.ico
UninstallDisplayIcon={app}\WinUI-App.ico
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
AllowCancelDuringInstall=no
VersionInfoVersion={#AppVersion}

[Messages]
SelectDirLabel3=Setup will place the installer files, uninstaller and installation log of [name] in the following folder. The app itself is deployed by Windows as an MSIX package.

[Files]
Source: "{#PackageDir}\{#PackageFile}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PackageDir}\{#CertificateFile}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\WinUI-App\Image\WinUI-App.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "Install-Helper.ps1"; Flags: dontcopy

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked
Name: "startmenuicon"; Description: "Create a &Start Menu shortcut"; GroupDescription: "Shortcuts:"

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Get-AppxPackage -Name '{#PackageIdentityName}' | Remove-AppxPackage"""; \
    Flags: runhidden waituntilterminated; \
    RunOnceId: "RemoveMsixPackage"

[UninstallDelete]
Type: files; Name: "{commondesktop}\{#AppName}.lnk"
Type: files; Name: "{commonprograms}\{#AppName}.lnk"
Type: files; Name: "{app}\installation.log"

[Code]
const
  ModeInstall   = 0;
  ModeUpdate    = 1;
  ModeReinstall = 2;

  StepWaiting = 0;
  StepRunning = 1;
  StepDone    = 2;
  StepFailed  = 3;

  ExitNewerVersion = 3;   { Install-Helper.ps1: newer version already installed }

var
  { detection / chosen action }
  AppAlreadyInstalled: Boolean;
  InstalledVersion: String;
  SetupMode: Integer;
  HelperScript: String;
  AumidFile: String;
  UninstallLogFile: String;

  { outcome }
  InstallSucceeded: Boolean;
  InstallExitCode: Integer;
  ShortcutsFailed: Boolean;
  UninstallCompleted: Boolean;

  { "already installed" page }
  ExistingPage: TWizardPage;
  ExistingTitle: TNewStaticText;
  ExistingInfo: TNewStaticText;
  UpdateButton: TNewButton;
  ReinstallButton: TNewButton;
  UninstallButton: TNewButton;
  UpdateText: TNewStaticText;
  ReinstallText: TNewStaticText;
  UninstallText: TNewStaticText;
  BusyBar: TNewProgressBar;
  BusyLabel: TNewStaticText;
  BusyHint: TNewStaticText;
  ResultLabel: TNewStaticText;
  ResultHint: TNewStaticText;

  { installing page }
  StepLabel1: TNewStaticText;
  StepLabel2: TNewStaticText;
  StepLabel3: TNewStaticText;

  { finished page }
  OpenAppButton: TNewButton;
  ShowLogButton: TNewButton;

{ ---------------------------------------------------------------------------
  Small helpers
  --------------------------------------------------------------------------- }

function UninstallKeyPath: String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{' + '{#AppIdValue}' + '}_is1';
end;

function StripQuotes(S: String): String;
begin
  S := Trim(S);
  if (Length(S) >= 2) and (S[1] = '"') and (S[Length(S)] = '"') then
    S := Copy(S, 2, Length(S) - 2);
  Result := S;
end;

function CurrentAppDir: String;
begin
  Result := RemoveBackslashUnlessRoot(WizardDirValue);
end;

function InstallLogPath: String;
begin
  Result := AddBackslash(CurrentAppDir) + 'installation.log';
end;

function PowerShellExe: String;
begin
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

function RunHelper(const Action, ExtraArgs: String; var ResultCode: Integer): Boolean;
var
  Params: String;
begin
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + AddQuotes(HelperScript) +
    ' -Action ' + Action +
    ' -PackageName ' + AddQuotes('{#PackageIdentityName}') +
    ExtraArgs;
  Result := Exec(PowerShellExe, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if not Result then
    ResultCode := -1;
end;

procedure OpenLogFile(const Path: String);
var
  ResultCode: Integer;
begin
  if FileExists(Path) then
    Exec(ExpandConstant('{win}\notepad.exe'), AddQuotes(Path), '', SW_SHOWNORMAL, ewNoWait, ResultCode)
  else
    MsgBox('The log file could not be found:' + #13#10 + Path, mbInformation, MB_OK);
end;

function MakeLabel(AParent: TWinControl; ALeft, ATop, AWidth, ASize: Integer;
  ABold, AWrap: Boolean; const ACaption: String): TNewStaticText;
begin
  Result := TNewStaticText.Create(AParent);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.WordWrap := AWrap;
  Result.Font.Size := ASize;
  if ABold then
    Result.Font.Style := [fsBold];
  Result.Caption := ACaption;
end;

function MakeButton(AParent: TWinControl; ALeft, ATop, AWidth, AHeight: Integer;
  const ACaption: String): TNewButton;
begin
  Result := TNewButton.Create(AParent);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.Caption := ACaption;
  Result.Font.Size := 10;
  Result.Font.Style := [fsBold];
end;

{ ---------------------------------------------------------------------------
  Detect an existing installation (package and/or installer registry entry)
  --------------------------------------------------------------------------- }

procedure DetectExistingInstallation;
var
  ResultCode: Integer;
  DetectFile: String;
  Raw: AnsiString;
begin
  AppAlreadyInstalled := False;
  InstalledVersion := '';
  DetectFile := ExpandConstant('{tmp}\installed-version.txt');
  DeleteFile(DetectFile);

  if RunHelper('Detect', ' -InfoFile ' + AddQuotes(DetectFile), ResultCode) and (ResultCode = 0) then
  begin
    AppAlreadyInstalled := True;
    if LoadStringFromFile(DetectFile, Raw) then
      InstalledVersion := Trim(String(Raw));
  end;

  { a leftover entry from a previous run of this installer also counts }
  if RegKeyExists(HKLM64, UninstallKeyPath) or RegKeyExists(HKLM, UninstallKeyPath) then
  begin
    AppAlreadyInstalled := True;
    if InstalledVersion = '' then
    begin
      if not RegQueryStringValue(HKLM64, UninstallKeyPath, 'DisplayVersion', InstalledVersion) then
        RegQueryStringValue(HKLM, UninstallKeyPath, 'DisplayVersion', InstalledVersion);
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Installing page: thick progress bar + prominent step checklist
  --------------------------------------------------------------------------- }

function ActionName: String;
begin
  if SetupMode = ModeUpdate then
    Result := 'Update'
  else if SetupMode = ModeReinstall then
    Result := 'Reinstall'
  else
    Result := 'Install';
end;

function Step2Text: String;
begin
  if SetupMode = ModeUpdate then
    Result := 'Update the app package'
  else if SetupMode = ModeReinstall then
    Result := 'Reinstall the app package'
  else
    Result := 'Install the app package';
end;

function WantDesktopShortcut: Boolean;
begin
  Result := (SetupMode = ModeInstall) and WizardIsTaskSelected('desktopicon');
end;

function WantStartMenuShortcut: Boolean;
begin
  Result := (SetupMode = ModeInstall) and WizardIsTaskSelected('startmenuicon');
end;

function WantShortcuts: Boolean;
begin
  Result := WantDesktopShortcut or WantStartMenuShortcut;
end;

procedure SetStep(Lbl: TNewStaticText; const Text: String; State: Integer);
begin
  if State = StepDone then
  begin
    Lbl.Caption := '[ OK ]   ' + Text;
    Lbl.Font.Style := [];
    Lbl.Font.Color := clGreen;
  end
  else if State = StepRunning then
  begin
    Lbl.Caption := '[ >> ]   ' + Text + ' ...';
    Lbl.Font.Style := [fsBold];
    Lbl.Font.Color := clHighlight;
  end
  else if State = StepFailed then
  begin
    Lbl.Caption := '[ !! ]   ' + Text + ' - FAILED';
    Lbl.Font.Style := [fsBold];
    Lbl.Font.Color := clRed;
  end
  else
  begin
    Lbl.Caption := '[     ]   ' + Text;
    Lbl.Font.Style := [];
    Lbl.Font.Color := clGrayText;
  end;
end;

procedure PrepareInstallingPage;
var
  Y: Integer;
begin
  { make the progress bar much taller so it cannot be missed }
  WizardForm.ProgressGauge.Height := ScaleY(30);
  Y := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height + ScaleY(20);

  StepLabel1 := MakeLabel(WizardForm.InstallingPage, 0, Y, WizardForm.ProgressGauge.Width, 10, False, False, '');
  StepLabel2 := MakeLabel(WizardForm.InstallingPage, 0, Y + ScaleY(28), WizardForm.ProgressGauge.Width, 10, False, False, '');
  StepLabel3 := MakeLabel(WizardForm.InstallingPage, 0, Y + ScaleY(56), WizardForm.ProgressGauge.Width, 10, False, False, '');
end;

procedure DeployPackage;
var
  ResultCode: Integer;
  AppDirNow, CommonArgs, ShortcutArgs: String;
begin
  InstallSucceeded := False;
  ShortcutsFailed := False;
  InstallExitCode := -1;

  AppDirNow := CurrentAppDir;
  DeleteFile(AumidFile);

  CommonArgs :=
    ' -AppDir ' + AddQuotes(AppDirNow) +
    ' -PackageFile ' + AddQuotes(AppDirNow + '\{#PackageFile}') +
    ' -CertificateFile ' + AddQuotes(AppDirNow + '\{#CertificateFile}') +
    ' -IconFile ' + AddQuotes(AppDirNow + '\WinUI-App.ico') +
    ' -LogFile ' + AddQuotes(InstallLogPath) +
    ' -InfoFile ' + AddQuotes(AumidFile) +
    ' -ShortcutName ' + AddQuotes('{#AppName}');

  { step 1 is finished: the installer files have been copied }
  SetStep(StepLabel1, 'Copy installer files', StepDone);
  SetStep(StepLabel2, Step2Text, StepRunning);
  WizardForm.StatusLabel.Caption := 'Deploying the app package. Please wait - this can take a minute...';
  WizardForm.FileNameLabel.Caption := '';
  WizardForm.ProgressGauge.Style := npbstMarquee;   { moving bar = work in progress }

  RunHelper(ActionName, CommonArgs, ResultCode);
  InstallExitCode := ResultCode;

  if ResultCode = 0 then
  begin
    SetStep(StepLabel2, Step2Text, StepDone);

    if WantShortcuts then
    begin
      SetStep(StepLabel3, 'Create shortcuts', StepRunning);
      ShortcutArgs := '';
      if WantDesktopShortcut then
        ShortcutArgs := ShortcutArgs + ' -DesktopShortcut';
      if WantStartMenuShortcut then
        ShortcutArgs := ShortcutArgs + ' -StartMenuShortcut';

      RunHelper('Shortcuts', CommonArgs + ShortcutArgs, ResultCode);
      ShortcutsFailed := ResultCode <> 0;
      if ShortcutsFailed then
        SetStep(StepLabel3, 'Create shortcuts', StepFailed)
      else
        SetStep(StepLabel3, 'Create shortcuts', StepDone);
    end;

    InstallSucceeded := True;
  end
  else
    SetStep(StepLabel2, Step2Text, StepFailed);

  WizardForm.ProgressGauge.Style := npbstNormal;
  WizardForm.ProgressGauge.Position := WizardForm.ProgressGauge.Max;
end;

{ ---------------------------------------------------------------------------
  "Already installed" page: Update / Reinstall / Uninstall
  --------------------------------------------------------------------------- }

procedure ShowOptions(AVisible: Boolean);
begin
  ExistingTitle.Visible := AVisible;
  ExistingInfo.Visible := AVisible;
  UpdateButton.Visible := AVisible;
  ReinstallButton.Visible := AVisible;
  UninstallButton.Visible := AVisible;
  UpdateText.Visible := AVisible;
  ReinstallText.Visible := AVisible;
  UninstallText.Visible := AVisible;
end;

procedure SetWorking(Working: Boolean);
begin
  ShowOptions(not Working);
  BusyBar.Visible := Working;
  BusyLabel.Visible := Working;
  BusyHint.Visible := Working;
  WizardForm.CancelButton.Enabled := not Working;
  if Working then
    BusyBar.Style := npbstMarquee
  else
    BusyBar.Style := npbstNormal;
end;

procedure StartInstallFlow(Mode: Integer);
begin
  SetupMode := Mode;
  { give the navigation buttons back before leaving this page }
  WizardForm.NextButton.Visible := True;
  WizardForm.BackButton.Visible := True;
  WizardForm.NextButton.OnClick(WizardForm.NextButton);
end;

procedure UpdateButtonClick(Sender: TObject);
begin
  StartInstallFlow(ModeUpdate);
end;

procedure ReinstallButtonClick(Sender: TObject);
begin
  StartInstallFlow(ModeReinstall);
end;

procedure UninstallButtonClick(Sender: TObject);
var
  ResultCode: Integer;
  UninstallString, UninstallExe, Args: String;
begin
  if MsgBox('Remove {#AppName} from this computer?' + #13#10 + #13#10 +
    'Local data stored by the app will be deleted.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES then
    Exit;

  UninstallExe := '';
  UninstallString := '';
  if not RegQueryStringValue(HKLM64, UninstallKeyPath, 'UninstallString', UninstallString) then
    RegQueryStringValue(HKLM, UninstallKeyPath, 'UninstallString', UninstallString);
  if UninstallString <> '' then
    UninstallExe := StripQuotes(UninstallString);

  UninstallLogFile := ExpandConstant('{%TEMP}\{#AppName}-uninstall.log');

  Args := ' -UninstallRegKey ' + AddQuotes(UninstallKeyPath) +
    ' -LogFile ' + AddQuotes(UninstallLogFile) +
    ' -ShortcutName ' + AddQuotes('{#AppName}');
  if UninstallExe <> '' then
    Args := Args + ' -UninstallExe ' + AddQuotes(UninstallExe);

  SetWorking(True);
  BusyLabel.Caption := 'Uninstalling {#AppName}...';
  RunHelper('Uninstall', Args, ResultCode);
  SetWorking(False);

  if ResultCode = 0 then
  begin
    ShowOptions(False);
    ResultLabel.Visible := True;
    ResultHint.Visible := True;
    UninstallCompleted := True;
    WizardForm.CancelButton.Caption := '&Close';
  end
  else
  begin
    if MsgBox('{#AppName} could not be uninstalled.' + #13#10 + #13#10 +
      'Do you want to open the log file to see what went wrong?',
      mbError, MB_YESNO) = IDYES then
      OpenLogFile(UninstallLogFile);
  end;
end;

procedure CreateExistingPage;
var
  S: TWinControl;
  W: Integer;
  VersionText: String;
begin
  ExistingPage := CreateCustomPage(wpWelcome, 'Existing installation found',
    '{#AppName} is already installed on this computer.');
  S := ExistingPage.Surface;
  W := S.Width;

  if InstalledVersion <> '' then
    VersionText := 'Installed version: ' + InstalledVersion
  else
    VersionText := 'Installed version: unknown';

  ExistingTitle := MakeLabel(S, 0, 0, W, 11, True, False, 'Choose what to do with {#AppName}');
  ExistingInfo := MakeLabel(S, 0, ScaleY(26), W, 9, False, False,
    VersionText + '     |     This installer: {#AppVersion}');

  UpdateButton := MakeButton(S, 0, ScaleY(60), ScaleX(124), ScaleY(36), '&Update');
  UpdateButton.OnClick := @UpdateButtonClick;
  UpdateText := MakeLabel(S, ScaleX(136), ScaleY(62), W - ScaleX(136), 9, False, True,
    'Install version {#AppVersion} over the existing one. Your app data is kept.');

  ReinstallButton := MakeButton(S, 0, ScaleY(110), ScaleX(124), ScaleY(36), '&Reinstall');
  ReinstallButton.OnClick := @ReinstallButtonClick;
  ReinstallText := MakeLabel(S, ScaleX(136), ScaleY(112), W - ScaleX(136), 9, False, True,
    'Remove the app and install it again from scratch. Local app data will be reset.');

  UninstallButton := MakeButton(S, 0, ScaleY(160), ScaleX(124), ScaleY(36), 'U&ninstall');
  UninstallButton.OnClick := @UninstallButtonClick;
  UninstallText := MakeLabel(S, ScaleX(136), ScaleY(162), W - ScaleX(136), 9, False, True,
    'Remove {#AppName} from this computer. Local app data will be deleted.');

  { shown only while uninstalling }
  BusyBar := TNewProgressBar.Create(ExistingPage);
  BusyBar.Parent := S;
  BusyBar.Left := 0;
  BusyBar.Top := ScaleY(64);
  BusyBar.Width := W;
  BusyBar.Height := ScaleY(30);
  BusyBar.Visible := False;

  BusyLabel := MakeLabel(S, 0, ScaleY(106), W, 12, True, False, 'Uninstalling {#AppName}...');
  BusyLabel.Font.Color := clHighlight;
  BusyLabel.Visible := False;
  BusyHint := MakeLabel(S, 0, ScaleY(138), W, 9, False, True,
    'Please wait. Do not close this window until the uninstall has finished.');
  BusyHint.Visible := False;

  { shown after a successful uninstall }
  ResultLabel := MakeLabel(S, 0, ScaleY(40), W, 14, True, True, '{#AppName} has been uninstalled.');
  ResultLabel.Font.Color := clGreen;
  ResultLabel.Visible := False;
  ResultHint := MakeLabel(S, 0, ScaleY(90), W, 10, False, True, 'Click Close to exit Setup.');
  ResultHint.Visible := False;
end;

{ ---------------------------------------------------------------------------
  Finished page: [Open App] and [Show Log]
  --------------------------------------------------------------------------- }

procedure OpenAppButtonClick(Sender: TObject);
var
  Raw: AnsiString;
  Aumid: String;
  ResultCode: Integer;
begin
  Aumid := '';
  if LoadStringFromFile(AumidFile, Raw) then
    Aumid := Trim(String(Raw));

  if Aumid = '' then
  begin
    MsgBox('Could not locate the installed app. Please start it from the Start menu.', mbError, MB_OK);
    Exit;
  end;

  Exec(ExpandConstant('{win}\explorer.exe'), 'shell:AppsFolder\' + Aumid, '',
    SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

procedure ShowLogButtonClick(Sender: TObject);
begin
  OpenLogFile(InstallLogPath);
end;

procedure ConfigureFinishedPage;
var
  Heading, Detail: String;
  BtnWidth, BtnTop: Integer;
begin
  if InstallSucceeded then
  begin
    if SetupMode = ModeUpdate then
      Heading := 'Update complete'
    else if SetupMode = ModeReinstall then
      Heading := 'Reinstall complete'
    else
      Heading := 'Installation complete';

    Detail := '{#AppName} was set up successfully. Click Open App to start it now, ' +
      'or Show Log to review the installation log.';
    if ShortcutsFailed then
      Detail := Detail + #13#10 + #13#10 + 'The shortcuts could not be created. See the log for details.';
    WizardForm.FinishedHeadingLabel.Font.Color := clGreen;
  end
  else
  begin
    Heading := 'Installation failed';
    if InstallExitCode = ExitNewerVersion then
      Detail := 'A newer version of {#AppName} is already installed. ' +
        'Run Setup again and choose Reinstall to replace it.'
    else
      Detail := '{#AppName} could not be installed. Click Show Log to see what went wrong.';
    WizardForm.FinishedHeadingLabel.Font.Color := clRed;
  end;

  WizardForm.FinishedHeadingLabel.Font.Style := [fsBold];
  WizardForm.FinishedHeadingLabel.Caption := Heading;
  WizardForm.FinishedLabel.Caption := Detail;
  WizardForm.FinishedLabel.AdjustHeight;

  BtnWidth := (WizardForm.FinishedLabel.Width - ScaleX(10)) div 2;
  BtnTop := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(24);

  if OpenAppButton = nil then
  begin
    OpenAppButton := MakeButton(WizardForm.FinishedPage, WizardForm.FinishedLabel.Left, BtnTop,
      BtnWidth, ScaleY(38), '&Open App');
    OpenAppButton.OnClick := @OpenAppButtonClick;

    ShowLogButton := MakeButton(WizardForm.FinishedPage,
      WizardForm.FinishedLabel.Left + BtnWidth + ScaleX(10), BtnTop,
      BtnWidth, ScaleY(38), 'Show &Log');
    ShowLogButton.OnClick := @ShowLogButtonClick;
  end;

  OpenAppButton.Enabled := InstallSucceeded;
  ShowLogButton.Enabled := True;
end;

{ ---------------------------------------------------------------------------
  Inno Setup events
  --------------------------------------------------------------------------- }

procedure InitializeWizard;
begin
  ExtractTemporaryFile('Install-Helper.ps1');
  HelperScript := ExpandConstant('{tmp}\Install-Helper.ps1');
  AumidFile := ExpandConstant('{tmp}\app-aumid.txt');

  DetectExistingInstallation;
  if AppAlreadyInstalled then
    SetupMode := ModeUpdate      { default for silent runs }
  else
    SetupMode := ModeInstall;

  CreateExistingPage;
  PrepareInstallingPage;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if AppAlreadyInstalled then
  begin
    { the Update / Reinstall / Uninstall page replaces Welcome; shortcuts are only asked on first install }
    if (PageID = wpWelcome) or (PageID = wpSelectTasks) then
      Result := True;
  end
  else if PageID = ExistingPage.ID then
    Result := True;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = ExistingPage.ID then
  begin
    { the three big buttons are the only way forward on this page }
    WizardForm.NextButton.Visible := False;
    WizardForm.BackButton.Visible := False;
  end
  else if CurPageID = wpReady then
  begin
    if SetupMode = ModeUpdate then
      WizardForm.NextButton.Caption := '&Update'
    else if SetupMode = ModeReinstall then
      WizardForm.NextButton.Caption := '&Reinstall';
  end
  else if CurPageID = wpFinished then
    ConfigureFinishedPage;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    SetStep(StepLabel1, 'Copy installer files', StepRunning);
    SetStep(StepLabel2, Step2Text, StepWaiting);
    if WantShortcuts then
      SetStep(StepLabel3, 'Create shortcuts', StepWaiting);
  end
  else if CurStep = ssPostInstall then
    DeployPackage;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  { after a successful uninstall the Cancel button is "Close": exit without asking }
  if UninstallCompleted then
  begin
    Cancel := True;
    Confirm := False;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  Action: String;
begin
  if SetupMode = ModeUpdate then
    Action := 'Update the existing installation'
  else if SetupMode = ModeReinstall then
    Action := 'Reinstall (remove the app, then install it again)'
  else
    Action := 'New installation';

  Result := 'Action:' + NewLine + Space + Action + NewLine + NewLine +
    'Publisher:' + NewLine + Space + '{#PublisherName}' + NewLine + NewLine +
    MemoDirInfo + NewLine + NewLine;

  if (SetupMode = ModeInstall) and (MemoTasksInfo <> '') then
    Result := Result + MemoTasksInfo + NewLine + NewLine;

  Result := Result + 'Installation log:' + NewLine + Space + InstallLogPath;
end;
