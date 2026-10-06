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
; Owner-draw structure uses the default 32-bit Setup ABI; application remains x64.
SetupArchitecture=x86
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
type
  TLanguageDrawItem = record
    ControlType, ControlId, ItemId, Action, State: Cardinal;
    Window: HWND;
    DC: HDC;
    Bounds: TRect;
    Data: NativeInt;
  end;
var
  LanguageForm: TSetupForm;
  LanguageCombo: TNewComboBox;
  LanguageDrawCallback: NativeInt;

function CreateRoundRectRgn(Left, Top, Right, Bottom, Width, Height: Integer): THandle;
  external 'CreateRoundRectRgn@gdi32.dll stdcall';
function SetWindowRgn(Wnd: HWND; Region: THandle; Redraw: Boolean): Integer;
  external 'SetWindowRgn@user32.dll stdcall';
function GetCurrentProcessId: Cardinal;
  external 'GetCurrentProcessId@kernel32.dll stdcall';
function SetWindowSubclass(Wnd: HWND; Callback, Id, Data: NativeInt): Boolean;
  external 'SetWindowSubclass@comctl32.dll stdcall';
function RemoveWindowSubclass(Wnd: HWND; Callback, Id: NativeInt): Boolean;
  external 'RemoveWindowSubclass@comctl32.dll stdcall';
function DefSubclassProc(Wnd: HWND; Msg: LongWord; WParam, LParam: NativeInt): NativeInt;
  external 'DefSubclassProc@comctl32.dll stdcall';
procedure ReadDrawItem(var Item: TLanguageDrawItem; Source: NativeInt; Bytes: Cardinal);
  external 'RtlMoveMemory@kernel32.dll stdcall';
function NativeCreateBrush(Color: Cardinal): THandle;
  external 'CreateSolidBrush@gdi32.dll stdcall';
function NativeDeleteObject(Obj: THandle): Boolean;
  external 'DeleteObject@gdi32.dll stdcall';
function NativeFillRect(DC: HDC; var Bounds: TRect; Brush: THandle): Integer;
  external 'FillRect@user32.dll stdcall';
function NativeSetTextColor(DC: HDC; Color: Cardinal): Cardinal;
  external 'SetTextColor@gdi32.dll stdcall';
function NativeSetBkMode(DC: HDC; Mode: Integer): Integer;
  external 'SetBkMode@gdi32.dll stdcall';
function NativeDrawText(DC: HDC; Text: String; Count: Integer;
  var Bounds: TRect; Format: Cardinal): Integer;
  external 'DrawTextW@user32.dll stdcall';
function NativeGetSysColor(Index: Integer): Cardinal;
  external 'GetSysColor@user32.dll stdcall';
function NativeInvalidateRect(Wnd: HWND; Bounds: NativeInt; Erase: Boolean): Boolean;
  external 'InvalidateRect@user32.dll stdcall';

function LanguageDrawProc(Wnd: HWND; Msg: LongWord;
  WParam, LParam, Id, Data: NativeInt): NativeInt;
var
  Item: TLanguageDrawItem;
  Bounds: TRect;
  Brush: THandle;
  Background, Foreground: Cardinal;
  Caption: String;
  Selected: Boolean;
begin
  if (Msg = $002B) and (LParam <> 0) then begin
    ReadDrawItem(Item, LParam, 48);
    if (Item.ControlType = 3) and (Item.Window = LanguageCombo.Handle) and
      (Item.ItemId < 2) then begin
      Selected := ((Item.State and 1) <> 0) and LanguageCombo.DroppedDown;
      if IsDarkInstallMode then begin
        Background := $353535;
        Foreground := $F2F2F2;
        if Selected then Background := $615135;
      end else begin
        Background := NativeGetSysColor(5);
        Foreground := NativeGetSysColor(8);
        if Selected then begin
          if Background = $FFFFFF then Background := $F3EADD
          else begin
            Background := NativeGetSysColor(13);
            Foreground := NativeGetSysColor(14);
          end;
        end;
      end;
      Brush := NativeCreateBrush(Background);
      try NativeFillRect(Item.DC, Item.Bounds, Brush);
      finally NativeDeleteObject(Brush); end;
      NativeSetTextColor(Item.DC, Foreground);
      NativeSetBkMode(Item.DC, 1);
      Caption := LanguageCombo.Items[Item.ItemId];
      Bounds := Item.Bounds;
      Bounds.Left := Bounds.Left + ScaleX(14);
      Bounds.Right := Bounds.Right - ScaleX(30);
      NativeDrawText(Item.DC, Caption, Length(Caption), Bounds, $0824);
      if Selected then begin
        Bounds := Item.Bounds;
        Bounds.Left := Bounds.Right - ScaleX(24);
        NativeDrawText(Item.DC, '✓', 1, Bounds, $0824);
      end;
      Result := 1;
      Exit;
    end;
  end;
  Result := DefSubclassProc(Wnd, Msg, WParam, LParam);
end;

procedure UpdateLanguageDrawing(Sender: TObject);
begin
  if LanguageDrawCallback = 0 then Exit;
  if not SetWindowSubclass(LanguageForm.Handle, LanguageDrawCallback, 1, 0) then
    RaiseException('Could not initialize language selection.');
  SetWindowRgn(LanguageCombo.Handle,
    CreateRoundRectRgn(0, 0, LanguageCombo.Width + 1, LanguageCombo.Height + 1,
      ScaleX(12), ScaleY(12)), True);
  NativeInvalidateRect(LanguageCombo.Handle, 0, True);
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
      else Result := Result + StringOfChar('\', Slashes) + Value[I];
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
  ConfirmButton, CancelButton: TNewButton;
  ChosenLanguage, Arguments, RelaunchCommand: String;
  ErrorCode, I: Integer;
begin
  Result := True;
  if WizardSilent or (ExpandConstant('{param:LANG|}') <> '') then Exit;
  LanguageForm := CreateCustomForm(ScaleX(400), ScaleY(190), True, True);
  try
    LanguageForm.Caption := SetupMessage(msgSelectLanguageTitle);
    if ActiveLanguage = 'chinesesimplified' then LanguageForm.Font.Name := 'Microsoft YaHei UI'
    else LanguageForm.Font.Name := 'Segoe UI';
    LanguageForm.Font.Size := 10;
    LanguageForm.ClientWidth := ScaleX(400);
    LanguageForm.ClientHeight := ScaleY(190);
    LabelControl := TNewStaticText.Create(LanguageForm);
    LabelControl.Parent := LanguageForm;
    LabelControl.SetBounds(ScaleX(24), ScaleY(24), ScaleX(352), ScaleY(24));
    LabelControl.Caption := SetupMessage(msgSelectLanguageLabel);
    LabelControl.FocusControl := LanguageCombo;

    LanguageCombo := TNewComboBox.Create(LanguageForm);
    LanguageCombo.Parent := LanguageForm;
    LanguageCombo.Style := csOwnerDrawFixed;
    LanguageCombo.SetBounds(ScaleX(24), ScaleY(64), ScaleX(352), ScaleY(36));
    SendMessage(LanguageCombo.Handle, $0153, 0, ScaleY(30));
    SendMessage(LanguageCombo.Handle, $0153, -1, ScaleY(30));
    LanguageCombo.Items.Add('简体中文');
    LanguageCombo.Items.Add('English');
    LanguageCombo.DropDownCount := 2;
    LanguageCombo.TabOrder := 0;
    if ActiveLanguage = 'chinesesimplified' then LanguageCombo.ItemIndex := 0
    else LanguageCombo.ItemIndex := 1;
    LabelControl.FocusControl := LanguageCombo;

    ConfirmButton := TNewButton.Create(LanguageForm);
    ConfirmButton.Parent := LanguageForm;
    ConfirmButton.SetBounds(ScaleX(190), ScaleY(138), ScaleX(88), ScaleY(30));
    ConfirmButton.Caption := SetupMessage(msgButtonOK);
    ConfirmButton.ModalResult := mrOK;
    ConfirmButton.Default := True;
    ConfirmButton.TabOrder := 1;
    CancelButton := TNewButton.Create(LanguageForm);
    CancelButton.Parent := LanguageForm;
    CancelButton.SetBounds(ScaleX(288), ScaleY(138), ScaleX(88), ScaleY(30));
    CancelButton.Caption := SetupMessage(msgButtonCancel);
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;
    CancelButton.TabOrder := 2;

    LanguageDrawCallback := CreateCallback(@LanguageDrawProc);
    LanguageForm.OnShow := @UpdateLanguageDrawing;
    LanguageForm.OnResize := @UpdateLanguageDrawing;
    LanguageForm.CenterOnShow := True;
    LanguageForm.ActiveControl := LanguageCombo;
    Result := LanguageForm.ShowModal = mrOK;
    if not Result then Exit;
    if LanguageCombo.ItemIndex = 0 then ChosenLanguage := 'chinesesimplified'
    else ChosenLanguage := 'english';
    if ChosenLanguage <> ActiveLanguage then begin
      Arguments := '';
      for I := 1 to ParamCount do
        Arguments := Arguments + ' ' + QuoteSetupArgument(ParamStr(I));
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
    if LanguageDrawCallback <> 0 then
      RemoveWindowSubclass(LanguageForm.Handle, LanguageDrawCallback, 1);
    LanguageDrawCallback := 0;
    LanguageForm.Free;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'BoltSnip');
end;