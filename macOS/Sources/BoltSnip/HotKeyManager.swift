import Carbon
import Foundation

final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x424F4C54 // "BOLT"

    private init() {
        installEventHandler()
    }

    deinit {
        unregisterCurrent()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @discardableResult
    func register(_ hotKey: HotKey) -> Bool {
        unregisterCurrent()
        return registerWithoutRemovingExisting(hotKey)
    }

    @discardableResult
    func update(from oldHotKey: HotKey, to newHotKey: HotKey) -> Bool {
        unregisterCurrent()

        if registerWithoutRemovingExisting(newHotKey) {
            return true
        }

        _ = registerWithoutRemovingExisting(oldHotKey)
        return false
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async {
                    HotKeyManager.shared.onPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func registerWithoutRemovingExisting(_ hotKey: HotKey) -> Bool {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            return false
        }

        hotKeyRef = reference
        return true
    }

    private func unregisterCurrent() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}
