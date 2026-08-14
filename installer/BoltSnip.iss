#ifndef AppVersion
  #define AppVersion "0.12.0"
#endif

#ifndef SourceExecutable
  #define SourceExecutable "..\bin\BoltSnip.exe"
#endif

[Setup]
AppId={{A2E4C85C-1652-4E6F-9B6F-F1EAC7AF8844}
AppName=BoltSnip
AppVersion={#AppVersion}
AppVerName=BoltSnip {#AppVersion}
AppPublisher=VAR7IANT
AppPublisherURL=https://github.com/VAR7IANT/BoltSnip
AppSupportURL=https://github.com/VAR7IANT/BoltSnip/issues
AppUpdatesURL=https://github.com/VAR7IANT/BoltSnip/releases
DefaultDirName={localappdata}\Programs\BoltSnip
DefaultGroupName=BoltSnip
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=BoltSnip-Setup-{#AppVersion}-win-x64
SetupIconFile=..\bin\app-icon.ico
UninstallDisplayIcon={app}\BoltSnip.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=VAR7IANT
VersionInfoDescription=BoltSnip Windows Installer
VersionInfoProductName=BoltSnip
VersionInfoProductVersion={#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceExecutable}"; DestDir: "{app}"; DestName: "BoltSnip.exe"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\BoltSnip"; Filename: "{app}\BoltSnip.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\BoltSnip"; Filename: "{app}\BoltSnip.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\BoltSnip.exe"; Description: "{cm:LaunchProgram,BoltSnip}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'BoltSnip');
end;
