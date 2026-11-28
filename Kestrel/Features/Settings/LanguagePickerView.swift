import SwiftUI

/// Settings → Language: the app's own language, independent of the phone's.
struct LanguagePickerView: View {
    @AppStorage(AppLanguage.storageKey, store: SharedWallet.defaults) private var language: AppLanguage = .system
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SettingsGroup {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, option in
                        if index > 0 { Divider().padding(.leading, 16) }
                        Button {
                            Haptics.tap()
                            language = option
                        } label: {
                            row(option)
                        }
                        .accessibilityAddTraits(option == language ? .isSelected : [])
                    }
                }
                SettingsFootnote("Changes \(Brand.name) only. System dialogs, such as Face ID, follow your device's language.")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, 12)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ option: AppLanguage) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let name = option.nativeName {
                    Text(verbatim: name).foregroundStyle(Theme.Palette.textPrimary)
                    // The same language named in the current one, for anyone who can't read the native name.
                    if let translated = locale.localizedString(forIdentifier: option.rawValue), translated.localizedCaseInsensitiveCompare(name) != .orderedSame {
                        Text(verbatim: translated.localizedCapitalized).font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                    }
                } else {
                    Text("Device language").foregroundStyle(Theme.Palette.textPrimary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.accentText)
                .opacity(option == language ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
