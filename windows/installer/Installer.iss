; Installation, repair and removal are handled by unmodified Inno Setup.
#ifndef Product
  #error Product is required
#endif
[Setup]
AppId={#AppId}
AppName={#DisplayName}
AppVersion={#Version}
AppVerName={#DisplayName} {#Version}
AppPublisher=MBN
AppPublisherURL=https://app.mbnpro.ir/
DefaultDirName={localappdata}\Programs\{#DisplayName}
DefaultGroupName={#DisplayName}
#if Int(IsQa) != 0
PrivilegesRequired=lowest
#else
PrivilegesRequired=admin
#endif
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
UsePreviousAppDir=yes
UsePreviousTasks=yes
DisableProgramGroupPage=yes
DisableWelcomePage=no
CloseApplications=no
RestartApplications=no
SetupMutex=Local\{#AppId}.Installer
UninstallDisplayIcon={app}\{#Executable}
UninstallDisplayName={#DisplayName}
OutputDir={#OutputDir}
OutputBaseFilename=install-core
SetupIconFile={#IconFile}
VersionInfoVersion={#Version}.{#BuildNumber}
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern dark windows11 includetitlebar
WizardSizePercent=115
Uninstallable=yes
ChangesAssociations=no
ChangesEnvironment=no
SetupLogging=yes

[Languages]
Name: "fa"; MessagesFile: "{#SourcePath}Farsi.isl"

[Tasks]
Name: "desktopicon"; Description: "ساخت میان‌بر روی دسکتاپ"; GroupDescription: "میان‌برها:"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "LocalistRemote.exe,LocalistCamera*.dll"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BundleDir}\LocalistCamera*-{#Version}.{#BuildNumber}.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BundleDir}\LocalistRemote.exe"; DestDir: "{app}"; Attribs: hidden; Flags: ignoreversion
Source: "{#SourcePath}Vazirmatn-OFL.txt"; DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "{#UninstallShell}"; DestDir: "{app}"; DestName: "MBNUninstall.exe"; Flags: ignoreversion

[Icons]
Name: "{group}\{#DisplayName}"; Filename: "{app}\{#Executable}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#DisplayName}"; Filename: "{app}\{#Executable}"; WorkingDir: "{app}"; Tasks: desktopicon

#if Int(IsQa) == 0
[UninstallRun]
Filename: "{app}\{#Executable}"; Parameters: "--remove-windows-integration"; Flags: runhidden waituntilterminated; RunOnceId: "RemoveLocalistIntegration"
#endif

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#RegistryExe}"; ValueType: string; ValueName: ""; ValueData: "{app}\{#Executable}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#RegistryExe}"; ValueType: string; ValueName: "Path"; ValueData: "{app}"

[Code]
var IntegrationNeedsRestart: Boolean;
function NeedRestart(): Boolean;
begin
  Result := IntegrationNeedsRestart;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Key: String; ResultCode: Integer;
begin
#if Int(IsQa) == 0
  if CurStep = ssPostInstall then
    if not Exec(ExpandConstant('{app}\{#Executable}'), '--install-windows-integration',
       ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      RaiseException('نصب وبکم و میکروفون‌های Localist اجرا نشد. نصب را دوباره انجام دهید.')
    else if ResultCode = 3010 then
      IntegrationNeedsRestart := True
    else if ResultCode <> 0 then
      RaiseException('نصب دستگاه‌های Localist کامل نشد. امضای درایور، دسترسی ادمین و برنامه‌های استفاده‌کننده از دوربین و صدا را بررسی کنید.');
#endif
  if CurStep <> ssDone then Exit;
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#AppId}_is1';
  RegWriteStringValue(HKCU, Key, 'MBNUninstallCore', ExpandConstant('{uninstallexe}'));
  RegWriteStringValue(HKCU, Key, 'UninstallString', '"' + ExpandConstant('{app}\MBNUninstall.exe') + '"');
end;

function InitializeUninstall(): Boolean;
var ExitCode: Integer;
begin
  Result := True;
  { Directly opening Inno's core uses the same branded UI as Windows Settings.
    The branded UI calls the core silently, so this does not recurse. }
  if UninstallSilent then Exit;
  if FileExists(ExpandConstant('{app}\MBNUninstall.exe')) then
    if Exec(ExpandConstant('{app}\MBNUninstall.exe'), '', '', SW_SHOWNORMAL, ewNoWait, ExitCode) then
      Result := False;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var MS, LS: Cardinal;
begin
  Result := '';
  if GetVersionNumbers(ExpandConstant('{app}\{#Executable}'), MS, LS) then
    if (MS > {#VersionHigh}) or ((MS = {#VersionHigh}) and (LS > {#VersionLow})) then
      Result := 'نسخهٔ جدیدتری در این مسیر نصب است. برای حفظ نصب فعلی، نسخهٔ قدیمی‌تر نصب نمی‌شود.';
end;

procedure WriteProgress(CurProgress, MaxProgress: Integer);
var Target, Parent, Prefix, Token: String;
begin
  Target := ExpandConstant('{param:MBNProgressFile|}');
  { Only the wrapper's exact random Temp folder may receive progress. }
  Prefix := AddBackslash(GetEnv('TEMP')) + 'MBNSetup-';
  Parent := ExtractFileDir(Target);
  if (CompareText(ExtractFileName(Target), 'progress.txt') <> 0) or
     (Pos(Lowercase(Prefix), Lowercase(Parent)) <> 1) then Exit;
  Token := Copy(Parent, Length(Prefix) + 1, MaxInt);
  if (Length(Token) <> 32) or (Pos('\', Token) <> 0) or (Pos('/', Token) <> 0) then Exit;
  SaveStringToFile(Target, IntToStr(CurProgress) + '|' + IntToStr(MaxProgress), False);
end;

procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  WriteProgress(CurProgress, MaxProgress);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then WriteProgress(5, 100);
  if CurUninstallStep = usPostUninstall then WriteProgress(95, 100);
  if CurUninstallStep = usDone then WriteProgress(100, 100);
end;
