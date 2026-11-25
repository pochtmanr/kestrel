import Charts
import SwiftUI

/// The Currencies screen (pushed from the home card): what the wallet is worth, how it's split, and every
/// coin with its price and a 7-day sparkline. Tap a coin for its screen.
struct CurrenciesView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SharedWallet.hideBalanceKey, store: SharedWallet.defaults) private var hideBalance = false
    @AppStorage("currencies.sort") private var sort: CoinSort = .value
    @State private var query = ""

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var tokens: [TokenKind] {
        let matching = TokenKind.allCases.filter { $0.matches(query) }
        return sort.sorted(matching,
                           value: { app.holding(of: $0).usdValue(app.prices[$0]) },
                           change: { app.prices[$0]?.change24h })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if !searching {
                    PortfolioHeader(portfolio: Portfolio(holdings: TokenKind.allCases.map(app.holding(of:)), prices: app.prices),
                                    hasPrices: !app.prices.isEmpty,
                                    hidden: $hideBalance)
                }
                if tokens.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
                } else {
                    coinList
                    footer
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, 24)
            .readableWidth()
            .animation(.snappy, value: tokens)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.background)
        .navigationTitle("Currencies")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search coins"))
        .toolbar { sortMenu }
        .refreshable {
            async let prices: Void = app.refreshPrices()
            await app.refresh()
            await prices
        }
        .task { await app.refreshPrices() }
    }

    private var coinList: some View {
        VStack(spacing: 0) {
            ForEach(Array(tokens.enumerated()), id: \.element) { index, token in
                if index > 0 { Divider().padding(.leading, 72).padding(.trailing, 18) }
                NavigationLink(value: HomeRoute.coin(token)) {
                    CoinRow(token: token, holding: app.holding(of: token), quote: app.markets[token],
                            price: app.prices[token], hidden: hideBalance)
                }
                .buttonStyle(CoinRowPressStyle())
            }
        }
        .padding(.vertical, 6)
        .surface(cornerRadius: Theme.Radius.tile)
    }

    private var footer: some View {
        Group {
            if let updated = app.marketsUpdatedAt {
                Text("Prices from CoinGecko, in US dollars · updated \(updated, format: .relative(presentation: .named))")
            } else {
                Text("Prices unavailable right now. Your balances are up to date.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.Palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(CoinSort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityHint("Changes the order of your coins")
        }
    }
}

// MARK: - Header

private struct PortfolioHeader: View {
    let portfolio: Portfolio
    let hasPrices: Bool
    @Binding var hidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { hidden.toggle() }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Portfolio value")
                        Image(systemName: hidden ? "eye.slash" : "eye").font(.caption)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hidden ? "Show balances" : "Hide balances")

                Text(verbatim: hidden ? "••••••" : USDPrice.format(portfolio.total))
                    .font(Theme.Typography.amount(40, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let change = portfolio.change, let percent = portfolio.changePercent {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right").font(.caption.weight(.bold))
                        Text(verbatim: hidden ? "••••" : "\(USDPrice.signed(change)) (\(USDPrice.percent(percent)))")
                        Text("today").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(change >= 0 ? Theme.Palette.positive : Theme.Palette.danger)
                } else if !hasPrices {
                    Text("USDT counted at $1.00 until prices load")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .accessibilityElement(children: .combine)

            if !portfolio.slices.isEmpty {
                AllocationBar(slices: portfolio.slices, hidden: hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xs)
    }
}

/// One bar split by value, then a legend with each coin's share.
private struct AllocationBar: View {
    let slices: [Portfolio.Slice]
    let hidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            GeometryReader { geo in
                // Every slice gets a 4 pt floor so tiny shares stay visible; the rest splits by share.
                let free = geo.size.width - CGFloat(max(0, slices.count - 1)) * 3 - CGFloat(slices.count) * 4
                HStack(spacing: 3) {
                    ForEach(slices, id: \.token) { slice in
                        Capsule()
                            .fill(hidden ? Theme.Palette.surfaceRaised : slice.token.color)
                            .frame(width: 4 + max(0, free) * slice.share)
                    }
                }
            }
            .frame(height: 8)

            HStack(spacing: Theme.Spacing.l) {
                ForEach(slices, id: \.token) { slice in
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle().fill(slice.token.color).frame(width: 8, height: 8)
                        Text(verbatim: slice.token.symbol).foregroundStyle(Theme.Palette.textSecondary)
                        Text(verbatim: hidden ? "••" : Self.share(slice.share)).foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
            }
            .font(.footnote.weight(.medium).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hidden ? String(localized: "Allocation hidden")
                                   : slices.map { "\($0.token.symbol) \(Self.share($0.share))" }.joined(separator: ", "))
    }

    static func share(_ share: Double) -> String {
        // One decimal at the edges, so 99.5% never rounds up to a misleading 100%.
        share.formatted(.percent.precision(.fractionLength(share < 0.1 || share > 0.9 ? 1 : 0)).locale(USDPrice.locale))
    }
}

// MARK: - Rows

private struct CoinRow: View {
    let token: TokenKind
    let holding: Holding
    let quote: MarketQuote?
    let price: TokenPrice?
    let hidden: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 14) {
            TokenIcon(token: token, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: token.symbol).font(.body.weight(.semibold)).foregroundStyle(Theme.Palette.textPrimary)
                if let price {
                    HStack(spacing: 6) {
                        Text(verbatim: USDPrice.price(price.usd)).foregroundStyle(Theme.Palette.textSecondary)
                        if let change = price.change24h { PriceChange(percent: change) }
                    }
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                } else {
                    Text(verbatim: token.name).font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 4)
            if !typeSize.isAccessibilitySize {
                Sparkline(values: quote?.sparkline ?? [], rising: (quote?.change7d ?? 0) >= 0)
                    .frame(minWidth: 20, maxWidth: 52)
                    .frame(height: 26)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: hidden ? "••••" : holding.amount)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                if let value = holding.usdValue(price) {
                    Text(verbatim: hidden ? "••••" : USDPrice.format(value))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .lineLimit(1)
            // Amounts never truncate: the name column and sparkline give way first.
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens \(token.name)")
    }

    private var accessibilityText: String {
        var parts = [token.symbol]
        if !hidden {
            parts.append(holding.amount)
            if let value = holding.usdValue(price) { parts.append(String(localized: "about \(USDPrice.format(value))")) }
        }
        if let price {
            parts.append(String(localized: "price \(USDPrice.price(price.usd))"))
            if let change = price.change24h { parts.append(String(localized: "\(USDPrice.percent(change)) today")) }
        }
        return parts.joined(separator: ", ")
    }
}

/// A 7-day price line with no axes. A placeholder dash until data arrives.
struct Sparkline: View {
    let values: [Double]
    let rising: Bool

    var body: some View {
        if values.count > 1, let low = values.min(), let high = values.max() {
            let pad = max((high - low) * 0.1, high * 0.0001)
            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Hour", index), y: .value("Price", value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .foregroundStyle(rising ? Theme.Palette.positive : Theme.Palette.danger)
            }
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .accessibilityHidden(true)
        } else {
            Capsule()
                .fill(Theme.Palette.surfaceRaised)
                .frame(height: 2)
                .accessibilityHidden(true)
        }
    }
}

private struct CoinRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.Palette.surfaceRaised : .clear)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
