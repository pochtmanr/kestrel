import SwiftUI

/// Settings → Appearance: the theme, shown as small previews of the home
/// screen, and the text size.
struct AppearanceView: View {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @AppStorage(TextSize.storageKey) private var textSize = TextSize.systemIndex

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                SettingsGroup("Theme") {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Appearance.allCases) { option in
                            Button {
                                withAnimation(.snappy) { appearance = option }
                            } label: {
                                ThemeOption(appearance: option, selected: option == appearance)
                            }
                            .buttonStyle(CardPressStyle())
                            .accessibilityLabel(option.title)
                            .accessibilityAddTraits(option == appearance ? .isSelected : [])
                        }
                    }
                    .padding(14)
                }
                .sensoryFeedback(.selection, trigger: appearance)

                VStack(spacing: 10) {
                    SettingsGroup("Text size") {
                        VStack(alignment: .leading, spacing: 16) {
                            sample
                            Divider()
                            slider
                        }
                        .padding(16)
                    }
                    SettingsFootnote("The middle step follows the text size set in iOS Settings.")
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, 12)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A transfer row at the chosen size: what the setting changes, shown live.
    private var sample: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.left")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.Palette.positive)
                .frame(width: 36, height: 36)
                .background(Theme.Palette.positive.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Received").font(.body.weight(.semibold))
                Text("Today, 9:41").font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 8)
            Text(verbatim: "+250.00")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.Palette.positive)
        }
        .accessibilityElement(children: .combine)
    }

    private var slider: some View {
        HStack(spacing: 14) {
            Image(systemName: "textformat.size.smaller")
                .foregroundStyle(Theme.Palette.textSecondary)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { Double(textSize) }, set: { textSize = Int($0.rounded()) }),
                   in: 0...Double(TextSize.sizes.count - 1), step: 1)
                .tint(Theme.Palette.accent)
                .accessibilityLabel("Text size")
                .accessibilityValue(textSize == TextSize.systemIndex ? Text("Follows your device") : Text(verbatim: "\(textSize + 1) / \(TextSize.sizes.count)"))
            Image(systemName: "textformat.size.larger")
                .font(.title3)
                .foregroundStyle(Theme.Palette.textSecondary)
                .accessibilityHidden(true)
        }
        // The control itself stays one size: it mustn't jump under the thumb.
        .dynamicTypeSize(.large)
        .sensoryFeedback(.selection, trigger: textSize)
    }
}

/// One theme choice: a miniature of the home screen in that theme, its name,
/// and a tick when chosen.
private struct ThemeOption: View {
    let appearance: Appearance
    let selected: Bool

    var body: some View {
        VStack(spacing: 10) {
            preview
                .frame(height: 104)
                .clipShape(.rect(cornerRadius: Theme.Radius.m, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .strokeBorder(selected ? Theme.Palette.accentText : Theme.Palette.separator, lineWidth: selected ? 2 : 1)
                }
            Text(appearance.title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Theme.Palette.accentText : Theme.Palette.textTertiary)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var preview: some View {
        switch appearance {
        case .light: MiniHome().environment(\.colorScheme, .light)
        case .dark: MiniHome().environment(\.colorScheme, .dark)
        case .system:
            // Both at once, split down the middle: it follows the phone.
            ZStack {
                MiniHome().environment(\.colorScheme, .light)
                MiniHome().environment(\.colorScheme, .dark)
                    .mask(alignment: .trailing) {
                        GeometryReader { proxy in
                            Rectangle().frame(width: proxy.size.width / 2).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
            }
        }
    }
}

/// The home screen reduced to its shapes: balance, two actions, a card.
private struct MiniHome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Circle().fill(Theme.Palette.accent).frame(width: 12, height: 12)
            Capsule().fill(Theme.Palette.textPrimary).frame(width: 46, height: 9)
            Capsule().fill(Theme.Palette.textTertiary).frame(width: 28, height: 5)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: Theme.Radius.xxs, style: .continuous).fill(Theme.Palette.accent)
                RoundedRectangle(cornerRadius: Theme.Radius.xxs, style: .continuous).fill(Theme.Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xxs, style: .continuous).strokeBorder(Theme.Palette.separator))
            }
            .frame(height: 20)
            RoundedRectangle(cornerRadius: Theme.Radius.xxs, style: .continuous).fill(Theme.Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xxs, style: .continuous).strokeBorder(Theme.Palette.separator))
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.background)
        .accessibilityHidden(true)
    }
}
