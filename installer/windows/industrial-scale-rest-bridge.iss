; Compile via scripts/build-installer.ps1 on Windows.
#if VER < EncodeVer(6, 4, 0)
  #error Inno Setup 6.4 or later is required.
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef PublishDir
  #define PublishDir SourcePath + "..\..\dist\windows"
#endif
#ifndef InstallerOutputDir
  #define InstallerOutputDir SourcePath + "..\..\dist\installers"
#endif

[Setup]
AppId={{4ABBC7C9-965A-4E68-A1A1-73860A53BE44}
AppName=Industrial Scale REST Bridge
AppVersion={#AppVersion}
DefaultDirName={autopf}\IndustrialScaleRestBridge
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#InstallerOutputDir}
OutputBaseFilename=IndustrialScaleRestBridge-{#AppVersion}-win-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
SetupLogging=yes
UninstallLogging=yes
UninstallDisplayIcon={app}\scale.exe

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Files]
; Helpers first so early extraction need not decompress the application first.
Source: "prepare-settings.ps1"; Flags: dontcopy
Source: "{#PublishDir}\install-windows-service.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PublishDir}\uninstall-windows-service.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PublishDir}\*"; DestDir: "{app}"; Excludes: "settings.ini,*.pdb,install-windows-service.ps1,uninstall-windows-service.ps1"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{tmp}\prepared-settings.ini"; DestDir: "{app}"; DestName: "settings.ini"; Flags: external ignoreversion

[Code]
const
  ServiceKey = 'SYSTEM\CurrentControlSet\Services\IndustrialScaleRestBridge';

var
  ConfigPage: TInputFileWizardPage;
  PortPage: TWizardPage;
  PortEdit: TNewComboBox;
  PortStatus: TNewStaticText;
  RefreshButton: TNewButton;
  LastDirectory: String;
  PortsLoaded, ServiceTouched, HadService, HadSettings: Boolean;
  ServiceWasRunning, InstallAttempted, InstallationStarted, SetupSucceeded: Boolean;
  ServiceInstallFailed: Boolean;

function Quoted(const Value: String): String;
begin
  if (Pos('"', Value) > 0) or (Pos(#13, Value) > 0) or (Pos(#10, Value) > 0) then
    RaiseException('Die Eingabe enthält ungültige Zeichen.');
  Result := '"' + Value + '"';
end;

function RunPowerShell(const Script, Arguments: String; var Detail: String): Boolean;
var
  ExitCode, I: Integer;
  Output: TExecOutput;
begin
  Detail := '';
  Result := ExecAndCaptureOutput(
    ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + Quoted(Script) + ' ' + Arguments,
    '', SW_HIDE, ewWaitUntilTerminated, ExitCode, Output);
  if not Result then begin
    Detail := SysErrorMessage(ExitCode);
    Exit;
  end;
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do
    Detail := Detail + Output.StdOut[I] + #13#10;
  for I := 0 to GetArrayLength(Output.StdErr) - 1 do
    Detail := Detail + Output.StdErr[I] + #13#10;
  Log(Detail);
  Result := (ExitCode = 0) and not Output.Error;
end;

procedure RefreshPorts(Sender: TObject);
var
  ExitCode, I, Separator: Integer;
  Output: TExecOutput;
  Saved, Names, Name: String;
begin
  Saved := PortEdit.Text;
  PortEdit.Items.Clear;
  PortStatus.Caption := 'Ports werden ermittelt ...';
  try
    ExtractTemporaryFile('scale.exe');
    if not ExecAndCaptureOutput(ExpandConstant('{tmp}\scale.exe'), '--list-comports',
      ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ExitCode, Output) then
      RaiseException('Die Port-Erkennung konnte nicht gestartet werden.');
    if (ExitCode <> 0) or Output.Error then
      RaiseException('Die Port-Erkennung ist fehlgeschlagen.');
    for I := 0 to GetArrayLength(Output.StdOut) - 1 do begin
      if Pos('Available COM Ports:', Output.StdOut[I]) = 1 then begin
        Names := Trim(Copy(Output.StdOut[I], Length('Available COM Ports:') + 1, MaxInt));
        while Names <> '' do begin
          Separator := Pos(',', Names);
          if Separator = 0 then begin
            Name := Names;
            Names := '';
          end else begin
            Name := Copy(Names, 1, Separator - 1);
            Delete(Names, 1, Separator);
          end;
          if Trim(Name) <> '' then PortEdit.Items.Add(Trim(Name));
        end;
      end;
    end;
    if PortEdit.Items.Count = 0 then
      PortStatus.Caption := 'Keine Ports gefunden. Manuelle Eingabe ist weiterhin möglich.'
    else
      PortStatus.Caption := 'Port auswählen oder manuell eingeben. Leer = Wert der Vorlage beibehalten.';
  except
    Log(GetExceptionMessage);
    PortStatus.Caption := 'Port-Liste nicht verfügbar. Bitte bei Bedarf manuell eingeben.';
  end;
  PortEdit.Text := Saved;
end;

procedure InitializeWizard;
var
  LabelControl: TNewStaticText;
begin
  ConfigPage := CreateInputFilePage(wpSelectDir, 'Konfiguration auswählen',
    'Welche INI-Datei soll lokal übernommen werden?',
    'Die Vorlage wird nur gelesen und als settings.ini ins Programmverzeichnis kopiert. ' +
    'Für Netzwerkfreigaben können Sie einen Pfad wie \\server\freigabe\waage.ini eingeben.');
  ConfigPage.Add('INI-Vorlage:', 'INI-Dateien|*.ini|Alle Dateien|*.*', '.ini');
  ConfigPage.Values[0] := ExpandConstant('{param:CONFIG|}');

  PortPage := CreateCustomPage(ConfigPage.ID, 'COM-Port (optional)',
    'Bei Bedarf den COM-Port der gewählten Vorlage überschreiben.');
  LabelControl := TNewStaticText.Create(PortPage);
  LabelControl.Parent := PortPage.Surface;
  LabelControl.Caption := 'COM-Port auswählen oder eingeben (z. B. COM3):';
  LabelControl.AutoSize := True;
  PortEdit := TNewComboBox.Create(PortPage);
  PortEdit.Parent := PortPage.Surface;
  PortEdit.Top := LabelControl.Top + LabelControl.Height + ScaleY(8);
  PortEdit.Width := PortPage.SurfaceWidth - ScaleX(120);
  PortEdit.Style := csDropDown;
  PortEdit.Text := ExpandConstant('{param:COMPORT|}');
  RefreshButton := TNewButton.Create(PortPage);
  RefreshButton.Parent := PortPage.Surface;
  RefreshButton.Left := PortEdit.Width + ScaleX(8);
  RefreshButton.Top := PortEdit.Top;
  RefreshButton.Width := ScaleX(110);
  RefreshButton.Height := ScaleY(25);
  RefreshButton.Caption := 'Aktualisieren';
  RefreshButton.OnClick := @RefreshPorts;
  PortStatus := TNewStaticText.Create(PortPage);
  PortStatus.Parent := PortPage.Surface;
  PortStatus.Top := PortEdit.Top + ScaleY(38);
  PortStatus.Width := PortPage.SurfaceWidth;
  PortStatus.Height := ScaleY(60);
  PortStatus.WordWrap := True;
  PortStatus.Caption := 'Leer lassen, um den COM-Port der Vorlage beizubehalten.';
end;

procedure CurPageChanged(CurPageID: Integer);
var
  LocalSettings: String;
begin
  if (CurPageID = ConfigPage.ID) and (LastDirectory <> WizardDirValue) then begin
    LastDirectory := WizardDirValue;
    if ExpandConstant('{param:CONFIG|}') = '' then begin
      LocalSettings := AddBackslash(WizardDirValue) + 'settings.ini';
      if FileExists(LocalSettings) then ConfigPage.Values[0] := LocalSettings;
    end;
  end;
  if (CurPageID = PortPage.ID) and not PortsLoaded and not WizardSilent then begin
    PortsLoaded := True;
    RefreshPorts(nil);
  end;
  if (CurPageID = wpFinished) and ServiceInstallFailed then begin
    WizardForm.FinishedHeadingLabel.Caption := 'Installation fehlgeschlagen';
    WizardForm.FinishedLabel.Caption := 'Der Windows-Dienst konnte nicht gestartet werden. ' +
      'Bitte prüfen Sie die Konfiguration und das Setup-Protokoll. ' +
      'Sie können das Setup zur Reparatur erneut ausführen oder die Programmdateien deinstallieren.';
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = ConfigPage.ID then begin
    { Also runs during silent setup, where page-change callbacks are not relied on. }
    if (Trim(ConfigPage.Values[0]) = '') and FileExists(ExpandConstant('{app}\settings.ini')) then
      ConfigPage.Values[0] := ExpandConstant('{app}\settings.ini');
    if not FileExists(Trim(ConfigPage.Values[0])) then begin
      SuppressibleMsgBox('Bitte eine erreichbare INI-Datei auswählen. ' +
        'Falls ein Netzlaufwerk fehlt, verwenden Sie dessen UNC-Pfad (\\server\freigabe\datei.ini).', mbError, MB_OK, IDOK);
      Result := False;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Detail, Arguments: String;
  Stopped: Boolean;
begin
  Result := '';
  try
    ExtractTemporaryFile('prepare-settings.ps1');
    ExtractTemporaryFile('install-windows-service.ps1');
    ExtractTemporaryFile('uninstall-windows-service.ps1');
    Arguments := '-TemplatePath ' + Quoted(Trim(ConfigPage.Values[0])) +
      ' -DestinationPath ' + Quoted(ExpandConstant('{tmp}\prepared-settings.ini'));
    if Trim(PortEdit.Text) <> '' then Arguments := Arguments + ' -ComPort ' + Quoted(Trim(PortEdit.Text));
    if not RunPowerShell(ExpandConstant('{tmp}\prepare-settings.ps1'), Arguments, Detail) then begin
      Result := 'Die Konfiguration konnte nicht übernommen werden.' + #13#10 + Detail;
      Exit;
    end;
    if not ServiceTouched then begin
      HadService := RegKeyExists(HKLM64, ServiceKey);
      HadSettings := FileExists(ExpandConstant('{app}\settings.ini'));
      if HadSettings and not FileCopy(ExpandConstant('{app}\settings.ini'),
        ExpandConstant('{tmp}\previous-settings.ini'), False) then
        RaiseException('Die bisherige lokale Konfiguration konnte nicht gesichert werden.');
    end;
    Stopped := RunPowerShell(ExpandConstant('{tmp}\uninstall-windows-service.ps1'),
      '-StopOnly -ExpectedExecutablePath ' + Quoted(ExpandConstant('{app}\scale.exe')), Detail);
    if Pos('PreviousServiceStatus=', Detail) > 0 then begin
      ServiceWasRunning := ServiceWasRunning or (Pos('PreviousServiceStatus=Running', Detail) > 0);
      ServiceTouched := True;
    end;
    if not Stopped then begin
      Result := 'Der vorhandene Dienst konnte nicht sicher angehalten werden.' + #13#10 + Detail;
      Exit;
    end;
    ServiceTouched := True;
  except
    Result := GetExceptionMessage;
  end;
end;

procedure InstallService;
var
  Detail: String;
begin
  InstallAttempted := True;
  WizardForm.StatusLabel.Caption := 'Windows-Dienst wird installiert und gestartet ...';
  try
    ServiceInstallFailed := not RunPowerShell(ExpandConstant('{app}\install-windows-service.ps1'),
      '-UpdateExisting -ExecutablePath ' + Quoted(ExpandConstant('{app}\scale.exe')), Detail);
  except
    ServiceInstallFailed := True;
    Detail := GetExceptionMessage;
  end;
  if ServiceInstallFailed then begin
    Log('Dienstinstallation fehlgeschlagen: ' + Detail);
    SuppressibleMsgBox('Der Windows-Dienst konnte nicht gestartet werden. ' +
      'Die Installation ist fehlgeschlagen. Bitte prüfen Sie Konfiguration und Setup-Protokoll.' +
      #13#10 + Detail, mbError, MB_OK, IDOK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then InstallationStarted := True;
  { Inno catches postinstall exceptions. Record failures explicitly, including
    a nonzero process exit and a failure heading instead of a success screen. }
  if CurStep = ssPostInstall then InstallService;
  if CurStep = ssDone then SetupSucceeded := not ServiceInstallFailed;
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if ServiceInstallFailed then Result := 1;
end;

procedure DeinitializeSetup;
var
  Detail: String;
begin
  if SetupSucceeded then Exit;
  try
    if InstallationStarted then begin
      if HadSettings then begin
        if not FileCopy(ExpandConstant('{tmp}\previous-settings.ini'), ExpandConstant('{app}\settings.ini'), False) then
          Log('Die bisherige Konfiguration konnte nicht wiederhergestellt werden.');
      end else
        DeleteFile(ExpandConstant('{app}\settings.ini'));
    end;
    if InstallAttempted and not HadService then
      if not RunPowerShell(ExpandConstant('{tmp}\uninstall-windows-service.ps1'),
        '-ExpectedExecutablePath ' + Quoted(ExpandConstant('{app}\scale.exe')), Detail) then
        Log('Dienst-Rückabwicklung fehlgeschlagen: ' + Detail);
    if ServiceTouched and HadService and ServiceWasRunning then
      if not RunPowerShell(ExpandConstant('{tmp}\install-windows-service.ps1'),
        '-UpdateExisting -ExecutablePath ' + Quoted(ExpandConstant('{app}\scale.exe')), Detail) then
        Log('Der bisherige Dienst konnte nicht neu gestartet werden: ' + Detail);
  except
    Log('Setup-Rückabwicklung: ' + GetExceptionMessage);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Detail: String;
begin
  if CurUninstallStep = usUninstall then begin
    if not RunPowerShell(ExpandConstant('{app}\uninstall-windows-service.ps1'),
      '-ExpectedExecutablePath ' + Quoted(ExpandConstant('{app}\scale.exe')), Detail) then
      RaiseException('Der Dienst konnte nicht entfernt werden. Die Programmdateien bleiben erhalten.' + #13#10 + Detail);
  end;
end;
