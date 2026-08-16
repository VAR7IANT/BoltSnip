import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private var statusItem: NSStatusItem?
    private var captureMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.onPressed = { [weak self] in
            self?.captureArea()
        }

        if !HotKeyManager.shared.register(settingsStore.hotKey) {
            let fallback = HotKey.defaultCapture
            _ = HotKeyManager.shared.register(fallback)
            settingsStore.setHotKey(fallback)
        }

        configureStatusItem()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "BoltSnip")
            button.toolTip = "BoltSnip"
        }

        let menu = NSMenu()

        let capture = NSMenuItem(title: captureTitle(), action: #selector(captureArea), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        captureMenuItem = capture

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit BoltSnip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func captureTitle() -> String {
        "Capture Area    \(settingsStore.hotKey.displayString)"
    }

    private func refreshMenu() {
        captureMenuItem?.title = captureTitle()
    }

    @objc private func captureArea() {
        CaptureCoordinator.shared.startAreaCapture()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let content = SettingsView(store: settingsStore) { [weak self] in
                self?.refreshMenu()
            }

            let hostingView = NSHostingView(rootView: content)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "BoltSnip Settings"
            window.isReleasedWhenClosed = false
            window.contentView = hostingView
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
