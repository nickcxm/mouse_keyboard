import Foundation

final class SettingsStore {
    private enum Keys {
        static let speed = "KeyboardMouseController.speed"
        static let keyboardScrollInverted = "KeyboardMouseController.keyboardScrollInverted"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSpeed() -> KeyboardMouseController.SpeedPreset {
        let rawValue = userDefaults.integer(forKey: Keys.speed)
        return KeyboardMouseController.SpeedPreset(rawValue: rawValue) ?? .normal
    }

    func saveSpeed(_ speed: KeyboardMouseController.SpeedPreset) {
        userDefaults.set(speed.rawValue, forKey: Keys.speed)
    }

    func loadKeyboardScrollInverted() -> Bool {
        userDefaults.bool(forKey: Keys.keyboardScrollInverted)
    }

    func saveKeyboardScrollInverted(_ inverted: Bool) {
        userDefaults.set(inverted, forKey: Keys.keyboardScrollInverted)
    }
}
