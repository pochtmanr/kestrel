import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum Clipboard {
    /// Copies with an expiry and local-only flag, so a recovery phrase or
    /// address doesn't linger in the clipboard or sync via Handoff.
    static func copy(_ text: String, expiresIn seconds: TimeInterval = 120) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(seconds)]
        )
        Haptics.success()
    }

    static var string: String? { UIPasteboard.general.string }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

extension String {
    /// "TUEZSd…GWYdH"
    var shortAddress: String {
        count > 14 ? "\(prefix(6))…\(suffix(5))" : self
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code of your wallet address")
        }
    }

    private static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Primary full-width button.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(tint.opacity(isEnabled ? 1 : 0.35), in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .surface(cornerRadius: Theme.Radius.l)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Numbered grid of recovery words.
struct RecoveryWordsGrid: View {
    let phrase: String

    var body: some View {
        let words = phrase.split(separator: " ").map(String.init)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(word).font(.body.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .surface(cornerRadius: Theme.Radius.s)
            }
        }
    }
}

/// Keeps forms and cards readable on iPad instead of stretching edge to edge.
struct ReadableWidth: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: 560).frame(maxWidth: .infinity)
    }
}

extension View {
    func readableWidth() -> some View { modifier(ReadableWidth()) }
}

/// The app's look, chosen in Settings. System follows the phone.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A grouped panel: a solid slate card. A hairline keeps its edge in both
/// modes; on light a soft shadow too, or white melts into the pale page.
struct Surface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background {
            // Shadow on the panel shape only, so the text inside stays crisp.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.Palette.surface)
                .strokeBorder(Theme.Palette.separator, lineWidth: scheme == .light ? 0.5 : 1)
                .shadow(color: Color(red: 0.07, green: 0.10, blue: 0.16).opacity(scheme == .light ? 0.07 : 0), radius: 14, y: 6)
        }
    }
}

extension View {
    func surface(cornerRadius: CGFloat = Theme.Radius.card) -> some View { modifier(Surface(cornerRadius: cornerRadius)) }
}

/// Press feedback for big tappable cards: a gentle shrink, like a physical key.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

// MARK: Zoom transitions

/// A card grows into the screen it opens (iOS 18). Earlier systems get the
/// ordinary push or cover, so both helpers are no-ops there.
extension View {
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace) { $0.clipShape(.rect(cornerRadius: Theme.Radius.tile, style: .continuous)) }
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

/// A round glass icon button for screen chrome (settings, support).
struct GlassGlyph: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 44, height: 44)
                .modifier(RoundGlass())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The support button: one look everywhere — a round headphones button.
struct SupportButton: View {
    /// In a toolbar iOS 26 draws its own glass circle, so draw only the icon there.
    var inToolbar = false
    let action: () -> Void

    var body: some View {
        if !SupportConfig.isChatConfigured {
            EmptyView()
        } else if inToolbar, #available(iOS 26, *) {
            Button {
                Haptics.tap()
                action()
            } label: {
                Image(systemName: "headphones")
            }
            .accessibilityLabel("Support")
        } else {
            circle
        }
    }

    private var circle: some View {
        GlassGlyph(symbol: "headphones", label: "Support", action: action)
    }
}

/// The system's glass circle on iOS 26 (same as toolbar buttons); a solid
/// slate circle before that.
private struct RoundGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(Theme.Palette.surface, in: .circle)
                .overlay(Circle().strokeBorder(Theme.Palette.separator))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
    }
}
