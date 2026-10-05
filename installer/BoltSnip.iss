#ifndef AppVersion
  #error AppVersion must be supplied by build-installer.ps1
#endif

#ifndef ProductName
  #error ProductName must be supplied by build-installer.ps1
#endif

#ifndef SourceExecutable
  #define SourceExecutable "..\bin\BoltSnip.exe"
#endif

#ifndef SourceFfmpeg
  #error SourceFfmpeg must be supplied by build-installer.ps1
#endif

[Setup]
AppId={{A2E4C85C-1652-4E6F-9B6F-F1EAC7AF8844}
AppName={#ProductName}
AppVersion={#AppVersion}
AppVerName={#ProductName} {#AppVersion}
AppPublisher=VAR7IANT
AppPublisherURL=https://github.com/VAR7IANT/BoltSnip-Source
AppSupportURL=https://github.com/VAR7IANT/BoltSnip-Source/issues
AppUpdatesURL=https://github.com/VAR7IANT/BoltSnip-Source/releases
AppMutex=Local\BoltSnip.SingleInstance
DefaultDirName={localappdata}\Programs\BoltSnip
DefaultGroupName=BoltSnip
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename={#ProductName}-Setup-{#AppVersion}-win-x64
SetupIconFile={#ExtractFilePath(SourceExecutable)}app-icon.ico
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

Source: "{#SourceFfmpeg}"; DestDir: "{app}"; DestName: "ffmpeg.exe"; Flags: ignoreversion
Source: "third-party\FFmpeg-LICENSE.txt"; DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "third-party\FFmpeg-NOTICE.txt"; DestDir: "{app}\licenses"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#ProductName}"; Filename: "{app}\BoltSnip.exe"; WorkingDir: "{app}"
Name: "{autoprograms}\{cm:UninstallProgram,{#ProductName}}"; Filename: "{uninstallexe}"
Name: "{app}\{cm:UninstallProgram,{#ProductName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#ProductName}"; Filename: "{app}\BoltSnip.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\BoltSnip.exe"; Description: "{cm:LaunchProgram,{#ProductName}}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'BoltSnip');
end;
