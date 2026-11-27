import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func tr(_ key: String, _ values: CVarArg...) -> String {
        String(format: tr(key), arguments: values)
    }
}
