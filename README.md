# BoltSnip

> A lightweight, low-latency screenshot tool for Windows — invoke, select, copy.

BoltSnip 是一款追求“按下快捷键，马上拿到截图”的 Windows 轻量截图工具。它专注于低延迟、流畅框选和最短操作路径：全局快捷键唤起，自动吸附窗口或自由选择区域，然后直接复制到剪贴板。

## 特性

- 全局快捷键快速唤起，默认 `Alt+A`
- 多显示器与 Per-Monitor V2 高 DPI 支持
- 鼠标悬停自动吸附窗口
- 指针旁显示 10 倍像素放大镜、中心准星、坐标与颜色值，便于精确选点
- 8 ms 高频窗口跟踪与 8 px 边缘磁吸，快速移动时也能及时切换
- 自由拖动框选，局部重绘减少卡顿
- 方向键以 1 px 移动选区，`Shift + 方向键` 精调选区右侧或底部边缘
- 右键直接保存到默认目录，`Shift + 右键` 或 `Ctrl+S` 打开另存为
- 按物理像素 1:1 截取，裁剪过程不缩放、不重采样
- 剪贴板与 PNG 无损输出，JPEG 使用 95 高质量编码
- `Enter` / `Ctrl+C` 直接复制到剪贴板
- `Ctrl+S` 另存为 PNG 或 JPEG
- 托盘中自定义快捷键与快速保存目录，重启后保留
- 托盘中一键启用或关闭当前用户的 Windows 开机启动，无需管理员权限
- 专属托盘菜单样式：青色悬停轨、圆角勾选框、清晰分组与右对齐快捷键
- 勾选框按字体可见中心进行光学对齐，菜单行更整齐
- 单文件 EXE，无联网需求和第三方运行依赖
- 截图全程在本地完成
- 应用图标由构建脚本以矢量路径生成，无需额外二进制素材

## 使用

1. 启动 `BoltSnip.exe`，程序会常驻系统托盘。
2. 按 `Alt+A` 开始截图；若被占用，会尝试 `Ctrl+Shift+A`。
3. 移动鼠标选择窗口，或拖动鼠标自由框选。
4. 确定选区后，可用方向键逐像素移动；按住 `Shift` 再按方向键可缩放右侧或底部边缘。
5. 在任意位置单击左键立即复制，单击右键立即保存到默认目录。
6. `Shift + 右键` 或 `Ctrl+S` 可另存为，`Esc` 取消。
7. 右键托盘图标可设置快捷键、快速保存目录、开机启动或退出。

## 安装

从 GitHub Releases 下载 `BoltSnip-Setup-0.12.0-win-x64.exe` 并运行。安装器默认将
BoltSnip 安装到当前用户的 `%LOCALAPPDATA%\Programs\BoltSnip`，无需管理员权限，并创建
开始菜单快捷方式；桌面快捷方式可在安装时选择。

卸载 BoltSnip 时会移除程序文件、快捷方式和开机启动项，但会保留个人快捷键与保存目录
设置，方便以后重新安装。

## 快捷键设置

右键系统托盘中的 BoltSnip 图标，选择“设置快捷键…”，然后在输入框中直接按下新的组合键。快捷键至少需要包含 `Ctrl`、`Alt` 或 `Shift` 中的一项；如果组合键已被其他程序占用，BoltSnip 会保留原快捷键并提示更换。

从 InstantShot 旧版本升级时，BoltSnip 会自动迁移之前保存的快捷键配置。

## 快速保存

右键系统托盘中的 BoltSnip 图标，选择“设置保存目录…”。确定选区后单击右键会直接以无损 PNG 保存到该目录；尚未设置时默认使用系统“图片”目录下的 `BoltSnip` 文件夹。需要临时更改文件名、目录或保存为 JPEG 时，使用 `Shift + 右键` 或 `Ctrl+S`。

## 开机启动

右键系统托盘中的 BoltSnip 图标，单击“开机启动”即可启用或关闭。设置只作用于当前 Windows 用户，不需要管理员权限；菜单前出现勾选标记表示已经启用。

## 性能设计

- 截图窗口预先创建并复用，热路径不初始化复杂 UI。
- 使用 GDI `BitBlt` 一次抓取虚拟桌面。
- 选区使用原始像素直接拷贝，避免二次绘制造成清晰度损失。
- 拖动时只重绘变化区域和选区边框，放大镜移动时分别刷新新旧两个小区域。
- 使用 32 位预乘 Alpha 位图，减少绘制时的像素格式转换。
- 截图完成后立即释放全屏位图，后台只保留托盘和热键窗口。

## 构建

系统要求：Windows 10/11 与 .NET Framework 4.8。

在 PowerShell 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

构建结果位于 `bin\BoltSnip.exe`。构建过程使用 Windows 自带的 .NET Framework C# 编译器，无需下载依赖。

构建 Windows 安装包需要 Inno Setup 7。安装后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-installer.ps1
```

安装包输出到 `dist\BoltSnip-Setup-0.12.0-win-x64.exe`。

## 仓库简介

GitHub Description：

```text
A lightweight, low-latency screenshot tool for Windows — invoke, select, copy.
```

建议 Topics：`screenshot`、`screen-capture`、`windows`、`winforms`、`productivity`、`clipboard`。
