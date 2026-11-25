import SwiftUI

/// The search tab: every coin the wallet holds, with what you have and the
/// market price. Tap one for its screen, where you send or receive.
struct AssetSearchView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SharedWallet.hideBalanceKey, store: SharedWallet.defaults) private var hideBalance = false
    @Binding var query: String
    /// iOS 17: no search tab role, so the screen draws its own field.
    var ownsSearchField = false

    private static let all: [TokenKind] = [.usdt, .trx]

    private var results: [TokenKind] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Self.all }
        return Self.all.filter { token in
            ([token.symbol, token.name] + token.searchTerms).contains { $0.lowercased().contains(needle) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(results, id: \.self) { token in
                            NavigationLink(value: token) {
                                AssetSearchRow(token: token, holding: app.holding(of: token),
                                               price: app.prices[token], hidden: hideBalance)
                            }
                        }
                    } header: {
                        Text("Your coins")
                    } footer: {
                        if !app.prices.isEmpty {
                            Text("Prices from CoinGecko, in US dollars.")
                        }
                    }
                    .listRowBackground(Theme.Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.background)
            .navigationTitle("Coins")
            .modifier(OwnSearchField(enabled: ownsSearchField, query: $query))
            .navigationDestination(for: TokenKind.self) { AssetDetailView(token: $0) }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .receive: DepositView()
                case .fees: NetworkFeeInfoView()
                case .settings: SettingsView()
                }
            }
            .refreshable {
                await app.refresh()
                await app.refreshPrices()
            }
            .task { await app.refreshPrices() }
        }
    }
}

private struct OwnSearchField: ViewModifier {
    let enabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if enabled { content.searchable(text: $query, prompt: Text("USDT, TRX…")) } else { content }
    }
}

private struct AssetSearchRow: View {
    let token: TokenKind
    let holding: Holding
    let price: TokenPrice?
    let hidden: Bool

    var body: some View {
        HStack(spacing: 14) {
            TokenIcon(token: token, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(token.symbol).font(.body.weight(.semibold)).foregroundStyle(Theme.Palette.textPrimary)
                if let price {
                    HStack(spacing: 6) {
                        Text(price.usd.formatted(.currency(code: "USD").precision(.fractionLength(4))))
                        if let change = price.change24h { PriceChange(percent: change) }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text(token.name).font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(hidden ? "••••" : holding.amount)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let value = holding.usdValue(price) {
                    Text(hidden ? "••••" : value.formatted(.currency(code: "USD")))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// "+2.37%" in green, "−1.20%" in red.
struct PriceChange: View {
    let percent: Double

    var body: some View {
        Text((percent / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
            .foregroundStyle(percent >= 0 ? Theme.Palette.positive : Theme.Palette.danger)
    }
}

/// How much of a coin the wallet holds, ready to display.
struct Holding {
    let token: TokenKind
    let amount: String
    /// The holding as a plain number, for multiplying by a price.
    let quantity: Double

    func usdValue(_ price: TokenPrice?) -> Double? {
        guard let price else { return token == .usdt ? quantity : nil }
        return quantity * price.usd
    }
}

extension AppModel {
    func holding(of token: TokenKind) -> Holding {
        switch token {
        case .usdt: Holding(token: token, amount: USDT.format(units: usdtUnits), quantity: Double(usdtUnits) / 1_000_000)
        case .trx: Holding(token: token, amount: TRX.format(sun: trxSun), quantity: Double(trxSun) / 1_000_000)
        }
    }
}

extension TokenKind {
    /// Extra words people search by.
    var searchTerms: [String] {
        switch self {
        case .usdt: ["tether", "dollar", "stablecoin", "trc20", "trc-20"]
        case .trx: ["tron", "fee", "fees", "energy", "gas", "fuel"]
        }
    }
}

// MARK: - Coin screen

/// One coin: what you hold, its price, and what you can do with it.
struct AssetDetailView: View {
    let token: TokenKind
    @Environment(AppModel.self) private var app
    @AppStorage(SharedWallet.hideBalanceKey, store: SharedWallet.defaults) private var hideBalance = false

    var body: some View {
        let holding = app.holding(of: token)
        let price = app.prices[token]
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    TokenIcon(token: token, size: 64)
                    Text(hideBalance ? "••••" : "\(holding.amount) \(token.symbol)")
                        .font(Theme.Typography.amount(40, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let value = holding.usdValue(price), !hideBalance {
                        Text("≈ \(value.formatted(.currency(code: "USD")))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .combine)

                actions

                VStack(spacing: 0) {
                    infoRow("Price") {
                        if let price {
                            HStack(spacing: 8) {
                                Text(price.usd.formatted(.currency(code: "USD").precision(.fractionLength(4))))
                                if let change = price.change24h { PriceChange(percent: change).font(.subheadline) }
                            }
                        } else {
                            Text("Unavailable").foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    Divider().padding(.leading, 16)
                    infoRow("Network") { Text(token == .usdt ? "TRON · TRC-20" : "TRON") }
                    Divider().padding(.leading, 16)
                    infoRow("Used for") { Text(token == .usdt ? "Payments and savings" : "Network fees") }
                }
                .surface(cornerRadius: Theme.Radius.tile)

                if token == .trx {
                    Text("TRX pays the network fee for every USDT transfer, about 13–14 TRX each. Sending TRX itself isn't supported yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle(token.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            if token == .usdt {
                Button {
                    Haptics.tap()
                    app.sendRequest = .init()
                } label: {
                    Label("Send", systemImage: "arrow.up.right")
                }
                .buttonStyle(PrimaryButtonStyle())
                NavigationLink(value: HomeRoute.receive) {
                    Label("Receive", systemImage: "arrow.down.left")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                NavigationLink(value: HomeRoute.fees) {
                    Label("Add TRX", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func infoRow(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            value().foregroundStyle(Theme.Palette.textPrimary)
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}
