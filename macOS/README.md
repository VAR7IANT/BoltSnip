# BoltSnip for macOS

Native macOS implementation of BoltSnip, written in Swift with AppKit and SwiftUI.

## v0.1 foundation

The first macOS milestone focuses on the shortest useful screenshot path:

- menu bar app with no permanent Dock icon
- global capture shortcut, default `⌥A`
- user-configurable shortcut with conflict fallback
- shortcut persistence with `UserDefaults`
- multi-display overlay support
- free rectangular selection
- Retina-aware pixel size display
- automatic copy to the clipboard after selection
- `Esc` to cancel
- native screen-capture permission request

The Windows implementation remains untouched in the repository.

## Build

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- Swift 5.9 or newer

Build a local Apple Silicon app bundle:

```bash
cd macOS
./build-macos.sh
```

The result is written to:

```text
macOS/dist/BoltSnip.app
```

Launch it with:

```bash
open dist/BoltSnip.app
```

On the first capture attempt, macOS may ask for Screen Recording permission. Grant BoltSnip access in System Settings → Privacy & Security → Screen Recording, then invoke capture again.

## Shortcut editing

Open the BoltSnip menu bar item and choose **Settings…**. Click the shortcut button and press the new combination.

A shortcut must include at least one of Command (`⌘`), Option (`⌥`), or Control (`⌃`). Shift (`⇧`) can be added as an extra modifier. If macOS reports that the shortcut is already registered by another application, BoltSnip keeps the previous working shortcut.

## Next milestones

- window hover detection and magnetic window selection
- quick save and configurable output directory
- startup-at-login setting
- pixel magnifier, coordinates, and color values
- keyboard pixel-level selection adjustment
- lightweight annotation toolbar
