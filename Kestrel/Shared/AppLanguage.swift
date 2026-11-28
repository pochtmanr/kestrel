import Foundation

/// The language the app speaks, chosen in Settings. `system` follows the
/// phone. Stored in the App Group so the widget speaks it too.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case russian = "ru"
    case chinese = "zh-Hans"

    static let storageKey = "app.language"

    var id: String { rawValue }

    /// The saved choice. Read from defaults on each call, so code outside the
    /// view tree (errors, formatters, the widget) sees a change at once.
    static var current: AppLanguage {
        AppLanguage(rawValue: SharedWallet.defaults.string(forKey: storageKey) ?? "") ?? .system
    }

    /// Each language in its own words, so it can be found from any other.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .russian: "Русский"
        case .chinese: "简体中文"
        }
    }

    /// nil = leave the system's locale alone.
    var locale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }
}

/// A string built in code, in the app's chosen language. `String(localized:)`
/// alone follows the system language, not the choice made in Settings.
func tr(_ resource: LocalizedStringResource) -> String {
    guard let locale = AppLanguage.current.locale else { return String(localized: resource) }
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
}
