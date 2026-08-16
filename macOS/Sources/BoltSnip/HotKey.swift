import AppKit
import Carbon

struct HotKey: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyLabel: String

    static let defaultCapture = HotKey(
        keyCode: UInt32(kVK_ANSI_A),
        carbonModifiers: UInt32(optionKey),
        keyLabel: "A"
    )

    var displayString: String {
        var result = ""

        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }

        result += keyLabel
        return result
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Shift by itself would collide with normal typing, so require one
        // of Command, Option, or Control. Shift can still be added freely.
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
            return nil
        }

        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = modifiers
        self.keyLabel = HotKey.label(for: event)
    }

    private static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        default:
            let text = event.charactersIgnoringModifiers?.uppercased() ?? ""
            return text.isEmpty ? "Key \(event.keyCode)" : text
        }
    }
}
