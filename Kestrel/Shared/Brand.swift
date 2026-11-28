import Foundation

/// The app's own name and settings, read from its Info.plist so the app and
/// the widget agree without hard-coding them twice.
enum Brand {
    /// The name on the home screen.
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Kastrel"

    /// The App Group the app and its widget share.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? "group.com.simnetiq.kestrel"
}
