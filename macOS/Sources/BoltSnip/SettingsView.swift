import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let onHotKeyChanged: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BoltSnip")
                    .font(.system(size: 22, weight: .semibold))
                Text("Fast native screenshots for macOS")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture shortcut")
                        .fontWeight(.medium)
                    Text("Click the shortcut, then press a new key combination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HotKeyRecorderButton(hotKey: store.hotKey) { candidate in
                    apply(candidate)
                }
                .frame(width: 110, height: 30)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Restore Default") {
                    apply(.defaultCapture)
                }

                Spacer()

                Text("Default: ⌥A")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func apply(_ candidate: HotKey) {
        let current = store.hotKey

        if candidate == current {
            errorMessage = nil
            return
        }

        if HotKeyManager.shared.update(from: current, to: candidate) {
            store.setHotKey(candidate)
            errorMessage = nil
            onHotKeyChanged()
        } else {
            errorMessage = "That shortcut is already in use. Choose another one."
        }
    }
}

private struct HotKeyRecorderButton: NSViewRepresentable {
    let hotKey: HotKey
    let onRecord: (HotKey) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = onRecord
        button.title = hotKey.displayString
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onRecord = onRecord
        if !nsView.isRecording {
            nsView.title = hotKey.displayString
        }
    }
}

private final class RecorderButton: NSButton {
    var onRecord: ((HotKey) -> Void)?
    private(set) var isRecording = false
    private var previousTitle = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        previousTitle = title
        isRecording = true
        title = "Press keys…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            title = previousTitle
            return
        }

        guard let hotKey = HotKey(event: event) else {
            NSSound.beep()
            title = "Add ⌘ / ⌥ / ⌃"
            return
        }

        isRecording = false
        title = hotKey.displayString
        onRecord?(hotKey)
    }
}
