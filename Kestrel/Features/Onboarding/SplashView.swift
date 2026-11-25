import SwiftUI

/// The first second after launch. It starts exactly where the system launch
/// screen leaves off (night navy, the K centred at 64 pt) so the hand-off is
/// invisible, then lets the night sky and the name come up before the app.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            Theme.Palette.brandNight.ignoresSafeArea()
            BrandBackdrop()
                .opacity(revealed ? 0.55 : 0)

            Image("LogoGlyph")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.Palette.brandSky)
                .frame(height: 64)
                .shadow(color: Theme.Palette.brandSky.opacity(revealed ? 0.45 : 0), radius: 24)
                .scaleEffect(revealed && !reduceMotion ? 0.94 : 1)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 14) {
                        Text(verbatim: Brand.name.uppercased())
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .tracking(6)
                            .foregroundStyle(Theme.Palette.brandSky.opacity(0.9))
                        AsciiPulse()
                    }
                    .fixedSize()
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 64 : 56)
                }
        }
        // Light status bar over the navy while it's up, in either appearance.
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { revealed = true }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: Brand.name))
    }
}

/// A three-dot ASCII loader: `·  ·  ·` cycling through `· : +` like a
/// terminal waiting on the network.
private struct AsciiPulse: View {
    private static let ramp = ["·", ":", "+", ":"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.14)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.14)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    Text(verbatim: Self.ramp[(tick + 4 - index) % Self.ramp.count])
                        .frame(width: 10)
                }
            }
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.Palette.brandSky.opacity(0.6))
        }
        .accessibilityHidden(true)
    }
}

/// The brand photo (a figure under a dusk sky of ASCII stars), with a very
/// slow drift. Full screen by default; with `heightFraction` it covers only
/// the top part of the screen (still edge to edge), for content below it.
struct BrandBackdrop: View {
    var heightFraction: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            Image("WelcomeBackdrop")
                .resizable()
                .scaledToFill()
                .scaleEffect(drift ? 1.06 : 1, anchor: .top)
                .frame(width: proxy.size.width, height: proxy.size.height * heightFraction)
                .clipped()
        }
        .ignoresSafeArea()
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { drift = true }
            }
    }
}
