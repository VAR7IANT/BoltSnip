import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published private(set) var hotKey: HotKey

    private let defaults: UserDefaults
    private let hotKeyDefaultsKey = "captureHotKey"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: hotKeyDefaultsKey),
           let decoded = try? JSONDecoder().decode(HotKey.self, from: data) {
            hotKey = decoded
        } else {
            hotKey = .defaultCapture
        }
    }

    func setHotKey(_ hotKey: HotKey) {
        self.hotKey = hotKey

        if let data = try? JSONEncoder().encode(hotKey) {
            defaults.set(data, forKey: hotKeyDefaultsKey)
        }
    }
}
