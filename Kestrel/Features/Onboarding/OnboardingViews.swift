import SwiftUI

struct OnboardingView: View {
    enum Route: Hashable { case create, restore }
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(create: { path.append(.create) }, restore: { path.append(.restore) })
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .create: CreateWalletView()
                    case .restore: RestoreWalletView()
                    }
                }
        }
    }
}

/// The first screen: the brand photo across the top with the figure's lit
/// visor in clear view, fading into night where the promise and the two ways
/// in sit.
private struct WelcomeView: View {
    let create: () -> Void
    let restore: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.Palette.brandNight.ignoresSafeArea()
            BrandBackdrop(heightFraction: 0.74)
            scrim

            VStack(alignment: .leading, spacing: 0) {
                wordmark
                    .stagger(appeared, step: 0, reduceMotion: reduceMotion)
                Spacer(minLength: 24)

                Text(verbatim: "> self-custody · USDT · TRON_")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Palette.brandSky.opacity(0.75))
                    .accessibilityHidden(true)
                    .stagger(appeared, step: 1, reduceMotion: reduceMotion)

                Text("Your dollars.\nYour keys.")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(-2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isHeader)
                    .stagger(appeared, step: 1, reduceMotion: reduceMotion)

                Text("A USDT wallet that lives only on this phone. No account, no sign-up. Nobody else can move your money.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
                    .stagger(appeared, step: 2, reduceMotion: reduceMotion)

                VStack(spacing: 12) {
                    Button("Create a new wallet", action: create)
                        .buttonStyle(SkyButtonStyle())
                    Button("I already have a wallet", action: restore)
                        .buttonStyle(GlassOutlineButtonStyle())
                        .accessibilityHint("Restore with your recovery phrase")
                }
                .padding(.top, 28)
                .stagger(appeared, step: 3, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .readableWidth()
        }
        .environment(\.colorScheme, .dark)
        // Each piece animates itself in (see `stagger`), after the splash clears.
        .onAppear { appeared = true }
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            Image("LogoGlyph")
                .resizable()
                .scaledToFit()
                .frame(height: 26)
                .foregroundStyle(Theme.Palette.brandSky)
            Text(verbatim: Brand.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Brand.name))
    }

    /// Clear sky in the middle, night at the bottom for the text, a little
    /// shade at the top for the status bar and wordmark.
    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: Theme.Palette.brandNight.opacity(0.55), location: 0),
            .init(color: Theme.Palette.brandNight.opacity(0), location: 0.18),
            .init(color: Theme.Palette.brandNight.opacity(0), location: 0.42),
            .init(color: Theme.Palette.brandNight.opacity(0.85), location: 0.66),
            .init(color: Theme.Palette.brandNight, location: 0.78),
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The welcome screen's main action: the logo's sky blue, night-navy text.
private struct SkyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.Palette.brandNight)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.Palette.brandSky, in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
            .shadow(color: Theme.Palette.brandSky.opacity(0.3), radius: 18, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// The quieter action over the photo: frosted glass with a hairline.
private struct GlassOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous).strokeBorder(.white.opacity(0.16)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private extension View {
    /// Rise-and-fade entrance, staggered by `step`; a plain fade with Reduce Motion.
    func stagger(_ shown: Bool, step: Int, reduceMotion: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .animation(.smooth(duration: 0.7).delay(0.35 + Double(step) * 0.08), value: shown)
    }
}

struct CreateWalletView: View {
    @Environment(AppModel.self) private var app
    @State private var phrase = ""
    @State private var acknowledged = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Write down these 12 words in order. They're the only way to restore your wallet if you lose this phone.")
                    .foregroundStyle(.secondary)

                if !phrase.isEmpty {
                    RecoveryWordsGrid(phrase: phrase)
                    Button {
                        Clipboard.copy(phrase, expiresIn: 60)
                    } label: {
                        Label("Copy (clears in 1 minute)", systemImage: "doc.on.doc")
                    }
                    .frame(maxWidth: .infinity)
                }

                Label {
                    Text("Never share these words. \(Brand.name) support will never ask for them, and we can't recover them for you.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Palette.warning)
                }
                .font(.subheadline)
                .padding()
                .background(Theme.Palette.warning.opacity(0.1), in: .rect(cornerRadius: Theme.Radius.m))

                Toggle("I've written down my recovery phrase", isOn: $acknowledged)
                    .tint(Theme.Palette.accent)

                Button("Continue") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!acknowledged || phrase.isEmpty)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Recovery phrase")
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard phrase.isEmpty else { return }
            do { phrase = try Mnemonic.generate() } catch { self.error = "Couldn't create a wallet on this device." }
        }
        .alert("Something went wrong", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func save() {
        do {
            try WalletVault.save(phrase)
            Haptics.success()
            app.walletCreated()
        } catch {
            self.error = "Couldn't save the wallet to the Keychain."
        }
    }
}

struct RestoreWalletView: View {
    @Environment(AppModel.self) private var app
    @State private var input = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var wordCount: Int { Mnemonic.normalize(input).split(separator: " ").count }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $input)
                    .frame(minHeight: 150)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
            } header: {
                Text("Recovery phrase")
            } footer: {
                Text("Enter your 12 or 24 words separated by spaces. \(wordCount) entered.")
            }

            Section {
                Button("Paste from clipboard") { input = Clipboard.string ?? input }
            }

            Section {
                Button("Restore wallet") { restore() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(![12, 15, 18, 21, 24].contains(wordCount))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Restore wallet")
        .onAppear { focused = true }
        .alert("Can't restore", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func restore() {
        guard Mnemonic.isValid(input) else {
            Haptics.error()
            error = "Those words aren't a valid recovery phrase. Check the spelling and order."
            return
        }
        do {
            try WalletVault.save(input)
            Haptics.success()
            app.walletCreated()
        } catch {
            self.error = "Couldn't save the wallet to the Keychain."
        }
    }
}
