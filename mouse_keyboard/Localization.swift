import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func tr(_ key: String, _ value: CVarArg) -> String {
        String(format: tr(key), value)
    }
}
