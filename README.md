# BoltSnip

> A lightweight, low-latency screenshot tool for Windows — invoke, select, copy.

BoltSnip 是一款追求“按下快捷键，马上拿到截图”的 Windows 轻量截图工具。它专注于低延迟、流畅框选和最短操作路径：全局快捷键唤起，自动吸附窗口或自由选择区域，然后直接复制到剪贴板。

## 特性

- 全局快捷键快速唤起，默认 `Alt+A`
- 多显示器与 Per-Monitor V2 高 DPI 支持
- 鼠标悬停自动吸附窗口
- 8 ms 高频窗口跟踪与 8 px 边缘磁吸，快速移动时也能及时切换
- 自由拖动框选，局部重绘减少卡顿
- `Enter` / `Ctrl+C` 直接复制到剪贴板
- `Ctrl+S` 保存 PNG 或 JPEG
- 托盘中自定义快捷键，重启后保留
- 单文件 EXE，无联网需求和第三方运行依赖
- 截图全程在本地完成
- 应用图标由构建脚本以矢量路径生成，无需额外二进制素材

## 使用

1. 启动 `BoltSnip.exe`，程序会常驻系统托盘。
2. 按 `Alt+A` 开始截图；若被占用，会尝试 `Ctrl+Shift+A`。
3. 移动鼠标选择窗口，或拖动鼠标自由框选。
4. 确定选区后，在任意位置单击左键立即复制，单击右键立即保存。
5. 也可按 `Enter` / `Ctrl+C` 复制，按 `Ctrl+S` 保存，按 `Esc` 取消。
6. 右键托盘图标可设置快捷键或退出。

## 快捷键设置

右键系统托盘中的 BoltSnip 图标，选择“设置快捷键…”，然后在输入框中直接按下新的组合键。快捷键至少需要包含 `Ctrl`、`Alt` 或 `Shift` 中的一项；如果组合键已被其他程序占用，BoltSnip 会保留原快捷键并提示更换。

从 InstantShot 旧版本升级时，BoltSnip 会自动迁移之前保存的快捷键配置。

## 性能设计

- 截图窗口预先创建并复用，热路径不初始化复杂 UI。
- 使用 GDI `BitBlt` 一次抓取虚拟桌面。
- 拖动时只重绘变化区域和选区边框。
- 使用 32 位预乘 Alpha 位图，减少绘制时的像素格式转换。
- 截图完成后立即释放全屏位图，后台只保留托盘和热键窗口。

## 构建

系统要求：Windows 10/11 与 .NET Framework 4.8。

在 PowerShell 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

构建结果位于 `bin\BoltSnip.exe`。构建过程使用 Windows 自带的 .NET Framework C# 编译器，无需下载依赖。

## 仓库简介

GitHub Description：

```text
A lightweight, low-latency screenshot tool for Windows — invoke, select, copy.
```

建议 Topics：`screenshot`、`screen-capture`、`windows`、`winforms`、`productivity`、`clipboard`。
