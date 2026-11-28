import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(PriceAlertStore.self) private var alerts
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @AppStorage(AppLanguage.storageKey, store: SharedWallet.defaults) private var language: AppLanguage = .system
    @State private var confirmErase = false
    @State private var copied = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                profile

                SettingsGroup("Wallet") {
                    NavigationLink { SecuritySettingsView() } label: {
                        SettingsRow(title: "Security", symbol: "lock.fill", color: Theme.Palette.accent)
                    }
                    SettingsDivider()
                    NavigationLink(value: HomeRoute.fees) {
                        SettingsRow(title: "Network fees", symbol: "bolt.fill", color: Theme.Palette.ember,
                                    value: "\(TRX.format(sun: app.trxSun)) TRX",
                                    valueColor: app.fuelLevel == .good ? nil : app.fuelLevel.color)
                    }
                }

                SettingsGroup("App settings") {
                    NavigationLink(value: HomeRoute.appearance) {
                        SettingsRow(title: "Appearance", symbol: "circle.lefthalf.filled", color: Theme.Palette.accent, value: appearance.title)
                    }
                    SettingsDivider()
                    NavigationLink(value: HomeRoute.language) {
                        SettingsRow(title: "Language", symbol: "globe", color: Theme.Palette.accent, value: language.nativeName ?? tr("Device language"))
                    }
                }

                SettingsGroup("About") {
                    NavigationLink { AboutView() } label: {
                        SettingsRow(title: "About \(Brand.name)", logo: true)
                    }
                    if let support = SupportConfig.support {
                        SettingsDivider()
                        Link(destination: support) {
                            SettingsRow(title: "Help & Support", symbol: "questionmark", color: Theme.Palette.accent, external: true)
                        }
                    }
                    if let privacy = SupportConfig.privacy {
                        SettingsDivider()
                        Link(destination: privacy) {
                            SettingsRow(title: "Privacy Policy", symbol: "hand.raised.fill", color: Theme.Palette.accent, external: true)
                        }
                    }
                    if let terms = SupportConfig.terms {
                        SettingsDivider()
                        Link(destination: terms) {
                            SettingsRow(title: "Terms of Service", symbol: "doc.text.fill", color: Theme.Palette.accent, external: true)
                        }
                    }
                }

                VStack(spacing: 10) {
                    SettingsGroup {
                        Button { confirmErase = true } label: {
                            SettingsRow(title: "Remove wallet", symbol: "trash.fill", color: Theme.Palette.danger, destructive: true, chevron: false)
                        }
                    }
                    SettingsFootnote("Your funds stay on the TRON network. You can restore the wallet later with your recovery phrase.")
                }

                Text(verbatim: "\(Brand.name) \(version)")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Remove wallet?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Remove wallet", role: .destructive) {
                app.eraseWallet()
                alerts.clear()
                PriceAlerts.scheduleBackgroundRefresh(store: alerts)
            }
        } message: {
            Text("Without your recovery phrase the funds can never be recovered. Make sure you've written it down.")
        }
    }

    private var profile: some View {
        Button {
            guard let address = app.address else { return }
            Clipboard.copy(address)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            HStack(spacing: 14) {
                WalletBadge(address: app.address ?? "").scaleEffect(1.3).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Main wallet").font(.title3.bold())
                    Group {
                        if copied { Text("Address copied") } else { Text(verbatim: (app.address ?? "").shortAddress) }
                    }
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Theme.Palette.positive : Color.secondary)
            }
            .padding(16)
            .contentShape(.rect)
            .surface(cornerRadius: Theme.Radius.tile)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Copies your wallet address")
    }
}

// MARK: - Security

private struct SecuritySettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var biometricsOn = Biometrics.isEnabled
    @State private var showPhrase = false
    @State private var askPIN = false
    @State private var confirmResetPIN = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsGroup {
                    Button(action: revealPhrase) {
                        SettingsRow(title: "Show recovery phrase", symbol: "key.horizontal.fill", color: Theme.Palette.ember)
                    }
                }
                SettingsFootnote("Your recovery phrase is the only backup of this wallet. Keep it offline.")

                SettingsGroup {
                    if Biometrics.kind != .none {
                        HStack(spacing: 14) {
                            SettingsIcon(symbol: Biometrics.symbol, color: Theme.Palette.accent)
                            Toggle(Biometrics.label, isOn: $biometricsOn).tint(Theme.Palette.accent)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 58)
                        .onChange(of: biometricsOn) { _, on in toggleBiometrics(on) }
                        SettingsDivider()
                    }
                    Button { confirmResetPIN = true } label: {
                        SettingsRow(title: "Change PIN", symbol: "number", color: Theme.Palette.accent)
                    }
                    SettingsDivider()
                    Button { app.lock() } label: {
                        SettingsRow(title: "Lock now", symbol: "lock.fill", color: Theme.Palette.accent, chevron: false)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, 12)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPhrase) { RecoveryPhraseSheet() }
        .sheet(isPresented: $askPIN) {
            ConfirmWithPINSheet(title: "Show recovery phrase") { showPhrase = true }
        }
        .confirmationDialog("Change your PIN?", isPresented: $confirmResetPIN, titleVisibility: .visible) {
            Button("Set a new PIN") { app.resetPIN() }
        } message: {
            Text("You'll create a new 6-digit PIN now.")
        }
    }

    private func revealPhrase() {
        guard Biometrics.isEnabled else { askPIN = true; return }
        Task {
            if await Biometrics.authenticate(reason: tr("Show your recovery phrase")) { showPhrase = true } else { askPIN = true }
        }
    }

    private func toggleBiometrics(_ on: Bool) {
        guard on != Biometrics.isEnabled else { return }
        guard on else { Biometrics.isEnabled = false; return }
        Task {
            if await Biometrics.authenticate(reason: tr("Enable \(Biometrics.label) for \(Brand.name)")) {
                Biometrics.isEnabled = true
            } else {
                biometricsOn = false
            }
        }
    }
}

// MARK: - About

private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Image("Logo").resizable().frame(width: 84, height: 84).clipShape(.rect(cornerRadius: Theme.Radius.card))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    Text("\(Brand.name)").font(.title2.bold())
                    Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                Text("A self-custody wallet: your keys never leave this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.screen)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pieces

/// A rounded group of rows, like the system's inset-grouped list, under an
/// optional small heading.
struct SettingsGroup<Content: View>: View {
    var title: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, 16)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }.surface(cornerRadius: Theme.Radius.tile)
        }
    }
}

struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 62) }
}

/// The small explanation under a group.
struct SettingsFootnote: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

/// The coloured rounded-square icon at the start of a row.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color.gradient, in: .rect(cornerRadius: Theme.Radius.xs))
    }
}

struct SettingsRow: View {
    let title: LocalizedStringKey
    var symbol = ""
    var color: Color = Theme.Palette.accent
    var logo = false
    var value: String?
    var valueColor: Color?
    var destructive = false
    var chevron = true
    /// Opens outside the app (a web page): an arrow instead of the push chevron.
    var external = false

    var body: some View {
        HStack(spacing: 14) {
            if logo {
                Image("LogoGlyph").resizable().scaledToFit().foregroundStyle(.white)
                    .padding(6)
                    .frame(width: 32, height: 32)
                    .background(Theme.Palette.accent.gradient, in: .rect(cornerRadius: Theme.Radius.xs))
            } else {
                SettingsIcon(symbol: symbol, color: color)
            }
            Text(title).foregroundStyle(destructive ? Theme.Palette.danger : Color.primary).lineLimit(1).minimumScaleFactor(0.85)
            Spacer()
            if let value {
                Text(verbatim: value).foregroundStyle(valueColor ?? Theme.Palette.textSecondary).lineLimit(1)
            }
            if external {
                Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
            } else if chevron {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .contentShape(.rect)
    }
}

private struct RecoveryPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phrase = WalletVault.mnemonic() ?? ""

    var body: some View {
        // iPad: a centred card, not a page-wide sheet.
        content.formSheetSizing()
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Anyone with these words can take your funds. Never share them or type them into a website.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .padding()
                        .background(Theme.Palette.warning.opacity(0.1), in: .rect(cornerRadius: Theme.Radius.m))
                    RecoveryWordsGrid(phrase: phrase)
                    Button {
                        Clipboard.copy(phrase, expiresIn: 60)
                    } label: {
                        Label("Copy (clears in 1 minute)", systemImage: "doc.on.doc")
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
                .readableWidth()
            }
            .navigationTitle("Recovery phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onDisappear { phrase = "" }
    }
}
