# BoltSnip

> A lightweight, low-latency screenshot tool for Windows — invoke, select, copy.

BoltSnip 是一款面向 Windows 的轻量截图工具，专注于快速唤起、流畅框选和尽可能短的截图操作路径。

## Features

- 全局快捷键快速唤起，默认 `Alt+A`
- 多显示器与 Per-Monitor V2 高 DPI 支持
- 鼠标悬停自动吸附窗口
- 10× 像素放大镜、中心准星、坐标与颜色值
- 自由拖动框选与像素级微调
- 左键复制、右键快速保存
- PNG 无损输出，支持 JPEG 保存
- 托盘快捷键、保存目录与开机启动设置
- 单文件应用，无需额外第三方运行依赖
- 截图处理在本地完成

## Download

Windows 10 / 11 x64 users can download the latest installer from **GitHub Releases**:

https://github.com/VAR7IANT/BoltSnip/releases/latest

Release assets use names such as:

`BoltSnip-Setup-<version>-win-x64.exe`

> BoltSnip is distributed as prebuilt software. This public repository does not contain the application source code.

## Usage

1. 安装并启动 BoltSnip。
2. 按 `Alt+A` 开始截图。
3. 移动鼠标选择窗口，或拖动鼠标自由框选。
4. 使用方向键进行像素级微调。
5. 左键复制到剪贴板，右键快速保存。
6. `Shift + 右键` 或 `Ctrl+S` 打开另存为。
7. 在系统托盘中调整快捷键、保存目录和开机启动设置。

## Install

运行从 Releases 下载的 Windows x64 安装包即可。BoltSnip 默认按当前用户安装，不需要管理员权限。

卸载时会移除程序文件、快捷方式和开机启动项；个人快捷键与保存目录设置会保留，方便后续重新安装。

## Verification

正式发布时，Release 页面会同时提供安装包的 SHA-256 校验值或校验文件。建议下载后进行完整性校验。

## Source Code

BoltSnip is currently distributed as closed-source software.

The source code, build scripts, internal tests, licensing implementation and private development files are **not included** in this repository or in release download packages.

## Issues

如果遇到 Bug 或希望提出功能建议，可以直接使用本仓库的 GitHub Issues。

## System Requirements

- Windows 10 / Windows 11
- x64
- .NET Framework 4.8

## Current Stable Release

**v1.0.0**

SHA-256 for `BoltSnip-Setup-1.0.0-win-x64.exe`:

`DE1353CE44E037191B5632447513A6F16D4170CED83AEA29F2FC19C32AA49685`

---

Copyright © VAR7IANT. All rights reserved.
