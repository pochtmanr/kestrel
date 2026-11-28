import SwiftUI

/// The text size chosen in Settings: seven steps of Dynamic Type. The middle
/// one is the system default and means "follow the phone".
enum TextSize {
    static let storageKey = "app.textSize"
    static let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
    static let systemIndex = 3

    /// nil = leave the system's size alone.
    static func override(for index: Int) -> DynamicTypeSize? {
        index == systemIndex || !sizes.indices.contains(index) ? nil : sizes[index]
    }
}

/// Applies the Settings choices that the whole view tree reads from the
/// environment: language and text size. (Theme is `preferredColorScheme` at the root.)
struct AppPreferences: ViewModifier {
    @AppStorage(AppLanguage.storageKey, store: SharedWallet.defaults) private var language: AppLanguage = .system
    @AppStorage(TextSize.storageKey) private var textSize = TextSize.systemIndex

    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.locale) { if let locale = language.locale { $0 = locale } }
            .transformEnvironment(\.dynamicTypeSize) { if let size = TextSize.override(for: textSize) { $0 = size } }
    }
}
