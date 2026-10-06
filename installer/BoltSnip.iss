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
; The Windows 11 style softens controls and the window frame in both themes.
; Inno Setup falls back to native controls in high-contrast mode.
WizardStyle=modern dynamic windows11 includetitlebar
; A custom language picker provides rounded fields and generously spaced rows.
ShowLanguageDialog=no
WizardSizePercent=110,110
DefaultDialogFontName=Segoe UI
WizardSmallImageFile=assets\wizard-icon.png
WizardSmallImageFileDynamicDark=assets\wizard-icon.png
WizardImageFile=assets\wizard-panel.png
WizardImageFileDynamicDark=assets\wizard-panel.png
WizardImageBackColor=$F5F5F5
WizardImageBackColorDynamicDark=$F5F5F5
DisableWelcomePage=no
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

[LangOptions]
english.DialogFontName=Segoe UI
english.DialogFontSize=10
english.WelcomeFontName=Segoe UI
english.WelcomeFontSize=18
chinesesimplified.DialogFontName=Microsoft YaHei UI
chinesesimplified.DialogFontSize=10
chinesesimplified.WelcomeFontName=Microsoft YaHei UI
chinesesimplified.WelcomeFontSize=18

[Messages]
english.SelectLanguageTitle=BoltSnip Setup
english.SelectLanguageLabel=Choose your installation language.
english.WelcomeLabel1=Install BoltSnip
english.WelcomeLabel2=Set up [name/ver] on your computer.%n%nChoose where to install and whether to add a desktop shortcut on the next pages.%n%nClose BoltSnip before continuing.
english.FinishedHeadingLabel=BoltSnip is ready
english.FinishedLabel=Installation is complete. Launch BoltSnip below, or open it later from the Start menu.
english.FinishedLabelNoIcons=Installation is complete. Launch BoltSnip below, or open it later from the installation folder.
chinesesimplified.SelectLanguageTitle=BoltSnip 安装
chinesesimplified.SelectLanguageLabel=请选择安装界面使用的语言。
chinesesimplified.WelcomeLabel1=安装 BoltSnip
chinesesimplified.WelcomeLabel2=即将安装 [name/ver]。%n%n接下来，你可以选择安装位置，并设置是否创建桌面快捷方式。%n%n请先退出正在运行的 BoltSnip，再继续安装。
chinesesimplified.FinishedHeadingLabel=BoltSnip 已准备就绪
chinesesimplified.FinishedLabel=安装完成。你可以立即启动 BoltSnip，也可以稍后从开始菜单打开。
chinesesimplified.FinishedLabelNoIcons=安装完成。你可以立即启动 BoltSnip，也可以稍后从安装目录打开。

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
var
  LanguageForm: TSetupForm;
  LanguageField, ChineseOption, EnglishOption: TBitmapButton;
  LanguageMenu: TPanel;
  ConfirmButton, CancelButton: TNewButton;
  LanguageIndex, PendingLanguage: Integer;

function CreateRoundRectRgn(Left, Top, Right, Bottom, Width, Height: Integer): THandle;
  external 'CreateRoundRectRgn@gdi32.dll stdcall';
function SetWindowRgn(Wnd: HWND; Region: THandle; Redraw: Boolean): Integer;
  external 'SetWindowRgn@user32.dll stdcall';
function GetCurrentProcessId: Cardinal;
  external 'GetCurrentProcessId@kernel32.dll stdcall';

procedure PaintLanguageButton(Button: TBitmapButton; const Text: String;
  Selected, IsField: Boolean);
var
  Image: TBitmap;
  Background, Fill, Border, Foreground: TColor;
  Y, X: Integer;
begin
  if IsDarkInstallMode then begin
    Background := $2B2B2B; Fill := $353535; Border := $595959; Foreground := $F2F2F2;
    if Selected then begin Fill := $615135; Border := $A58869; end;
  end else begin
    Background := $FFFFFF; Fill := $FFFFFF; Border := $D0C7BF; Foreground := $282420;
    if Selected then begin Fill := $F3EADD; Border := $B39874; end;
  end;
  Image := TBitmap.Create;
  try
    Image.Width := Button.Width;
    Image.Height := Button.Height;
    with Image.Canvas do begin
      Brush.Color := Background;
      Pen.Color := Background;
      Rectangle(0, 0, Image.Width, Image.Height);
      Brush.Color := Fill;
      Pen.Color := Border;
      RoundRect(0, 0, Image.Width, Image.Height, ScaleX(12), ScaleY(12));
      Font.Assign(LanguageForm.Font);
      Font.Color := Foreground;
      Y := (Image.Height - TextHeight(Text)) div 2;
      TextOut(ScaleX(14), Y, Text);
      X := Image.Width - ScaleX(22);
      Pen.Color := Foreground;
      Pen.Width := ScaleX(1);
      if IsField then begin
        MoveTo(X - ScaleX(4), Image.Height div 2 - ScaleY(2));
        LineTo(X, Image.Height div 2 + ScaleY(2));
        LineTo(X + ScaleX(4), Image.Height div 2 - ScaleY(2));
      end else if Selected then
        TextOut(X - ScaleX(4), Y, '✓');
    end;
    Button.Caption := Text;
    Button.Bitmap := Image;
  finally
    Image.Free;
  end;
end;

procedure RefreshLanguageChoice;
begin
  if LanguageIndex = 0 then PaintLanguageButton(LanguageField, '简体中文', False, True)
  else PaintLanguageButton(LanguageField, 'English', False, True);
  PaintLanguageButton(ChineseOption, '简体中文', PendingLanguage = 0, False);
  PaintLanguageButton(EnglishOption, 'English', PendingLanguage = 1, False);
end;

procedure SetLanguageMenuVisible(Visible: Boolean);
begin
  LanguageMenu.Visible := Visible;
  if Visible then begin
    PendingLanguage := LanguageIndex;
    LanguageForm.ClientHeight := ScaleY(280);
    ConfirmButton.Top := ScaleY(228);
    CancelButton.Top := ConfirmButton.Top;
  end else begin
    LanguageForm.ClientHeight := ScaleY(190);
    ConfirmButton.Top := ScaleY(138);
    CancelButton.Top := ConfirmButton.Top;
  end;
  RefreshLanguageChoice;
end;

procedure OpenLanguageMenu(Sender: TObject);
begin
  SetLanguageMenuVisible(not LanguageMenu.Visible);
end;

procedure ChooseLanguage(Sender: TObject);
begin
  if Sender = ChineseOption then LanguageIndex := 0 else LanguageIndex := 1;
  SetLanguageMenuVisible(False);
  LanguageForm.ActiveControl := LanguageField;
end;

procedure LanguageKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if LanguageMenu.Visible then begin
    if (Key = 38) or (Key = 40) then begin
      PendingLanguage := 1 - PendingLanguage;
      RefreshLanguageChoice;
      Key := 0;
    end else if Key = 13 then begin
      LanguageIndex := PendingLanguage;
      SetLanguageMenuVisible(False);
      Key := 0;
    end else if Key = 27 then begin
      SetLanguageMenuVisible(False);
      Key := 0;
    end;
  end else if (LanguageForm.ActiveControl = LanguageField) and
    ((Key = 13) or (Key = 32) or (Key = 38) or (Key = 40)) then begin
    SetLanguageMenuVisible(True);
    Key := 0;
  end;
end;

function QuoteSetupArgument(const Value: String): String;
var
  I, Slashes: Integer;
begin
  Result := '"';
  Slashes := 0;
  for I := 1 to Length(Value) do begin
    if Value[I] = '\' then Slashes := Slashes + 1
    else begin
      if Value[I] = '"' then
        Result := Result + StringOfChar('\', Slashes * 2 + 1) + '"'
      else
        Result := Result + StringOfChar('\', Slashes) + Value[I];
      Slashes := 0;
    end;
  end;
  Result := Result + StringOfChar('\', Slashes * 2) + '"';
end;

function QuotePowerShellValue(const Value: String): String;
begin
  Result := Value;
  StringChangeEx(Result, '''', '''''', True);
  Result := '''' + Result + '''';
end;

function InitializeSetup: Boolean;
var
  LabelControl: TNewStaticText;
  ChosenLanguage, Arguments, RelaunchCommand: String;
  ErrorCode, I: Integer;
begin
  Result := True;
  { Explicit /LANG and silent installs keep their native, single-process path. }
  if WizardSilent or (ExpandConstant('{param:LANG|}') <> '') then Exit;
    LanguageForm := CreateCustomForm(ScaleX(400), ScaleY(190), True, True);
  try
    LanguageForm.Caption := SetupMessage(msgSelectLanguageTitle);
    if ActiveLanguage = 'chinesesimplified' then
      LanguageForm.Font.Name := 'Microsoft YaHei UI'
    else
      LanguageForm.Font.Name := 'Segoe UI';
    LanguageForm.Font.Size := 10;
    LanguageForm.ClientWidth := ScaleX(400);
    LanguageForm.ClientHeight := ScaleY(190);

    LabelControl := TNewStaticText.Create(LanguageForm);
    LabelControl.Parent := LanguageForm;
    LabelControl.SetBounds(ScaleX(24), ScaleY(24), ScaleX(352), ScaleY(24));
    LabelControl.Caption := SetupMessage(msgSelectLanguageLabel);

    LanguageField := TBitmapButton.Create(LanguageForm);
    LanguageField.Parent := LanguageForm;
    LanguageField.SetBounds(ScaleX(24), ScaleY(64), ScaleX(352), ScaleY(36));
    LanguageField.OnClick := @OpenLanguageMenu;
    LanguageField.TabStop := True;
    LanguageField.TabOrder := 0;
    SetWindowRgn(LanguageField.Handle,
      CreateRoundRectRgn(0, 0, LanguageField.Width + 1, LanguageField.Height + 1,
        ScaleX(12), ScaleY(12)), True);
    if ActiveLanguage = 'chinesesimplified' then LanguageIndex := 0 else LanguageIndex := 1;
    PendingLanguage := LanguageIndex;

    LanguageMenu := TPanel.Create(LanguageForm);
    LanguageMenu.Parent := LanguageForm;
    LanguageMenu.SetBounds(ScaleX(24), ScaleY(108), ScaleX(352), ScaleY(84));
    LanguageMenu.BevelOuter := bvNone;
    LanguageMenu.Visible := False;
    LanguageMenu.TabOrder := 1;
    ChineseOption := TBitmapButton.Create(LanguageForm);
    ChineseOption.Parent := LanguageMenu;
    ChineseOption.SetBounds(0, 0, LanguageMenu.Width, ScaleY(38));
    ChineseOption.OnClick := @ChooseLanguage;
    ChineseOption.TabStop := True;
    ChineseOption.TabOrder := 0;
    EnglishOption := TBitmapButton.Create(LanguageForm);
    EnglishOption.Parent := LanguageMenu;
    EnglishOption.SetBounds(0, ScaleY(44), LanguageMenu.Width, ScaleY(38));
    EnglishOption.OnClick := @ChooseLanguage;
    EnglishOption.TabStop := True;
    EnglishOption.TabOrder := 1;
    RefreshLanguageChoice;

    ConfirmButton := TNewButton.Create(LanguageForm);
    ConfirmButton.Parent := LanguageForm;
    ConfirmButton.SetBounds(ScaleX(190), ScaleY(138), ScaleX(88), ScaleY(30));
    ConfirmButton.Caption := SetupMessage(msgButtonOK);
    ConfirmButton.ModalResult := mrOK;
    { Enter on the language field selects an option rather than confirming. }
    ConfirmButton.Default := False;
    ConfirmButton.TabOrder := 2;

    CancelButton := TNewButton.Create(LanguageForm);
    CancelButton.Parent := LanguageForm;
    CancelButton.SetBounds(ScaleX(288), ScaleY(138), ScaleX(88), ScaleY(30));
    CancelButton.Caption := SetupMessage(msgButtonCancel);
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;
    CancelButton.TabOrder := 3;

    LanguageForm.KeyPreview := True;
    LanguageForm.OnKeyDown := @LanguageKeyDown;
    LanguageForm.CenterOnShow := True;
    LanguageForm.ActiveControl := LanguageField;
    Result := LanguageForm.ShowModal = mrOK;
    if not Result then Exit;
    if LanguageIndex = 0 then ChosenLanguage := 'chinesesimplified'
    else ChosenLanguage := 'english';
    if ChosenLanguage <> ActiveLanguage then begin
      { Inno fixes its message language before InitializeSetup. Relaunch only
        when the user switches language. ParamStr omits internal loader flags. }
      Arguments := '';
      for I := 1 to ParamCount do
        Arguments := Arguments + ' ' + QuoteSetupArgument(ParamStr(I));
      { Wait for this instance to exit before opening the selected language. }
      RelaunchCommand := 'Wait-Process -Id ' + IntToStr(GetCurrentProcessId) +
        ' -ErrorAction SilentlyContinue; Start-Process -FilePath ' +
        QuotePowerShellValue(ExpandConstant('{srcexe}')) + ' -ArgumentList ' +
        QuotePowerShellValue(Arguments + ' /LANG=' + ChosenLanguage);
      if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
        '-NoProfile -NonInteractive -WindowStyle Hidden -Command ' +
        QuoteSetupArgument(RelaunchCommand), '', SW_HIDE, ewNoWait, ErrorCode) then
        MsgBox(SysErrorMessage(ErrorCode), mbError, MB_OK);
      Result := False;
    end;
  finally
    LanguageForm.Free;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'BoltSnip');
end;
