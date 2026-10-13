# BoltSnip

> A lightweight, low-latency screenshot tool for Windows — invoke, select, copy.

BoltSnip is a lightweight screenshot utility for Windows, designed for instant activation, smooth region selection, and a fast, streamlined capture workflow.

## Features

- Quick access via a global hotkey (default: `Alt+A`)
- Multiple-monitor and Per-Monitor V2 high-DPI support
- Automatic window snapping on hover
- 10× pixel magnifier, center crosshair, coordinates, and color values
- Freeform region selection with pixel-level adjustments
- Left-click to copy; right-click to save quickly
- Lossless PNG output and optional JPEG saving
- Tray settings for hotkeys, save directory, and launch at startup
- Self-contained application without additional third-party runtime dependencies
- All screenshots are processed locally

## Download

Windows 10 / 11 x64 users can download the latest installer from **GitHub Releases**:

https://github.com/VAR7IANT/BoltSnip/releases/latest

Release assets use names such as:

`BoltSnip-Setup-<version>-win-x64.exe`

> BoltSnip is distributed as prebuilt software. This public repository does not contain the application source code.

## Usage

1. Install and launch BoltSnip.
2. Press `Alt+A` to start capturing.
3. Hover over a window to select it, or drag to select a custom region.
4. Use the arrow keys for pixel-level adjustments.
5. Left-click to copy to the clipboard or right-click to save quickly.
6. Press `Shift + right-click` or `Ctrl+S` to open Save As.
7. Use the system tray to configure the hotkey, save directory, and startup behavior.

## Install

Run the Windows x64 installer downloaded from Releases. BoltSnip installs for the current user by default and does not require administrator privileges.

Uninstalling removes program files, shortcuts, and startup entries, while keeping personal hotkey and save-directory settings for future reinstalls.

## Verification

Official releases provide either the installer's SHA-256 checksum or a checksum file. Verify the downloaded installer before running it.

## Source Code

BoltSnip is currently distributed as closed-source software.

The source code, build scripts, internal tests, licensing implementation, and private development files are **not included** in this repository or release download packages.

## Issues

Use this repository's GitHub Issues to report bugs or request features.

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