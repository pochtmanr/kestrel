import SwiftUI

/// One coin: what you hold, its price over time, the market, and what you
/// can do with it. Pushed from the Currencies screen and the home card.
struct CoinDetailView: View {
    let token: TokenKind
    @Environment(AppModel.self) private var app
    @Environment(PriceAlertStore.self) private var alerts
    @AppStorage(SharedWallet.hideBalanceKey, store: SharedWallet.defaults) private var hideBalance = false
    /// The market card's extra rows, as the user left them.
    @AppStorage("coin.showsAllStats") private var showsAllStats = false
    @State private var range: PriceRange = .week
    @State private var chart = PriceChartLoader()
    @State private var selection: Date?
    @State private var expanded = false
    #if DEBUG
    @MainActor private static var debugFlagsApplied = false
    #endif
    /// From the weekly chart, so it arrives after the rest of the numbers.
    @State private var fiveYearChange: Double?
    @State private var detail: TokenTransfer?
    @Environment(\.isSplitShell) private var isSplitShell
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var holding: Holding { app.holding(of: token) }
    private var price: TokenPrice? { app.prices[token] }
    private var quote: MarketQuote? { app.markets[token] }
    private var points: [PricePoint] { chart.points(for: range) }
    private var selectedPoint: PricePoint? { selection.flatMap { points.nearest(to: $0) } }
    private var armedAlerts: Int { alerts.alerts(for: token).filter(\.isArmed).count }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header
                actions
                // Wide screens: the chart and its numbers beside the position,
                // market and history. One column reads in the same order.
                AdaptiveColumns(spacing: Theme.Spacing.l, leadingFraction: 0.55) {
                    priceSection
                    performanceCard
                    alertsRow
                } trailing: {
                    positionCard
                    if quote != nil { marketCard }
                    switch token {
                    case .usdt: transfersCard
                    case .trx: fuelCard
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, 32)
            .readableWidth(isSplitShell ? Theme.Layout.wideContent : Theme.Layout.readable)
        }
        .background(Theme.Palette.background)
        .navigationTitle(token.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: HomeRoute.alerts(token)) {
                    Image(systemName: armedAlerts > 0 ? "bell.fill" : "bell")
                }
                .accessibilityLabel("Price alerts")
                .accessibilityValue(armedAlerts > 0 ? Text("\(armedAlerts) active") : Text(verbatim: ""))
            }
        }
        .refreshable {
            async let prices: Void = app.refreshPrices()
            await app.refresh()
            await prices
            await loadChart()
            fiveYearChange = await app.fiveYearChange(for: token)
        }
        .task(id: range) { await loadChart() }
        .task { fiveYearChange = await app.fiveYearChange(for: token) }
        .fullScreenCover(isPresented: $expanded) {
            ExpandedChartView(token: token, range: $range, loader: chart)
        }
        #if DEBUG
        // `-coin-expanded` (with `-route coin-trx`): open the full-screen chart at launch, for screenshots.
        .onAppear {
            guard !Self.debugFlagsApplied else { return }
            Self.debugFlagsApplied = true
            if CommandLine.arguments.contains("-coin-expanded") { expanded = true }
        }
        #endif
        .sheet(item: $detail) { transfer in
            TransferDetailView(transfer: transfer, myAddress: app.address ?? "") { to in
                detail = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    app.sendRequest = .init(recipient: to)
                }
            }
        }
    }

    private func loadChart() async {
        await chart.load(token, range, from: app, animated: !reduceMotion)
    }

    private func select(_ newRange: PriceRange) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { range = newRange }
    }

    // MARK: Header and actions

    private var header: some View {
        VStack(spacing: 10) {
            TokenIcon(token: token, size: 64)
            Text(verbatim: hideBalance ? "•••• \(token.symbol)" : "\(holding.amount) \(token.symbol)")
                .font(Theme.Typography.amount(36, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let value = holding.usdValue(price) {
                Text(verbatim: hideBalance ? "≈ ••••" : "≈ \(USDPrice.format(value))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            switch token {
            case .usdt:
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
            case .trx:
                NavigationLink(value: HomeRoute.receiveToken(.trx)) {
                    Label("Add TRX", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                NavigationLink(value: HomeRoute.fees) {
                    Label("About fees", systemImage: "info.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: Price and chart

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                priceLabel
                Spacer(minLength: 0)
                expandButton
            }
            PriceChartView(loader: chart, range: range, showsExtremes: true, selection: $selection) {
                Task { await loadChart() }
            }
            .frame(height: isSplitShell ? 280 : 200)
            PriceRangePicker(selection: $range)
                .onChange(of: range) { selection = nil }
        }
        .padding(Theme.Spacing.l)
        .surface(cornerRadius: Theme.Radius.tile)
    }

    private var expandButton: some View {
        Button {
            Haptics.tap()
            selection = nil
            expanded = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 34, height: 34)
                .background(Theme.Palette.surfaceRaised, in: .circle)
                // A full-size target around the small circle.
                .frame(width: 44, height: 44, alignment: .topTrailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand chart")
        .accessibilityHint("Opens the chart full screen with volume")
    }

    @ViewBuilder
    private var priceLabel: some View {
        let shown = selectedPoint?.usd ?? price?.usd
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: shown.map(USDPrice.price) ?? "—")
                .font(Theme.Typography.amount(28, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: Theme.Spacing.xs) {
                if let point = selectedPoint {
                    Text(verbatim: range.scrubLabel(for: point.date))
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else if let change = rangeChange {
                    PriceChange(percent: change)
                    Text(range.caption).foregroundStyle(Theme.Palette.textTertiary)
                } else {
                    Text(price == nil ? "Price unavailable" : "Loading history…").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .font(.subheadline.weight(.medium).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    /// The change over the shown range; 24h straight from the quote for 1D.
    private var rangeChange: Double? {
        if range == .day, let change = price?.change24h { return change }
        return points.changePercent
    }

    // MARK: Performance

    /// The coin's return over each period the chart can show. The quote has
    /// them up to a year; five years comes from the weekly chart.
    private var performance: [Performance] {
        [Performance(range: .day, percent: quote?.change24h ?? price?.change24h),
         Performance(range: .week, percent: quote?.change7d),
         Performance(range: .month, percent: quote?.change30d),
         Performance(range: .year, percent: quote?.change1y),
         Performance(range: .fiveYears, percent: fiveYearChange)]
    }

    private var performanceCard: some View {
        let entries = performance
        // Big text: one period per row; otherwise five cells across.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: Theme.Spacing.xxs))
        return InfoCard(title: "Performance") {
            layout {
                ForEach(entries) { entry in
                    PerformanceCell(entry: entry, selected: entry.range == range, stacked: stacked) {
                        select(entry.range)
                    }
                }
            }
            .padding(.horizontal, stacked ? 0 : Theme.Spacing.m)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.s)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(performanceSummary(entries))
        }
    }

    private func performanceSummary(_ entries: [Performance]) -> String {
        let parts = entries.compactMap { entry in entry.percent.map { "\(entry.range.spokenTitle) \(Performance.text($0))" } }
        return ([tr("Performance")] + parts).joined(separator: ", ")
    }

    // MARK: Alerts

    private var alertsRow: some View {
        let armed = armedAlerts
        return NavigationLink(value: HomeRoute.alerts(token)) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: armed > 0 ? "bell.fill" : "bell")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accentText)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.surfaceRaised, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Price alerts")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Group {
                        if armed > 0 {
                            Text("\(armed) active")
                        } else {
                            Text("Get a notification when \(token.symbol) reaches a price you choose.")
                        }
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(cornerRadius: Theme.Radius.tile)
            .contentShape(.rect(cornerRadius: Theme.Radius.tile))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Cards

    private var positionCard: some View {
        let value = holding.usdValue(price)
        let portfolio = Portfolio(holdings: TokenKind.allCases.map(app.holding(of:)), prices: app.prices)
        let share = portfolio.slices.first { $0.token == token }?.share
        let today: Double? = {
            guard let value, let change = price?.change24h, change > -100 else { return nil }
            return value - value / (1 + change / 100)
        }()
        return InfoCard(title: "Your position") {
            InfoRow("Amount") { Text(verbatim: hideBalance ? "••••" : "\(holding.amount) \(token.symbol)") }
            InfoRow("Value") { Text(verbatim: hideBalance ? "••••" : value.map { USDPrice.format($0) } ?? "—") }
            if let today {
                InfoRow("Today") {
                    Text(verbatim: hideBalance ? "••••" : USDPrice.signed(today))
                        .foregroundStyle(hideBalance ? Theme.Palette.textPrimary : today >= 0 ? Theme.Palette.positive : Theme.Palette.danger)
                }
            }
            if let share, portfolio.slices.count > 1 {
                InfoRow("Share of portfolio") {
                    Text(verbatim: hideBalance ? "••" : share.formatted(.percent.precision(.fractionLength(1)).locale(USDPrice.locale)))
                }
            }
            InfoRow("Network") { Text(token.network) }
            InfoRow("Used for") { Text(token.usedFor) }
        }
    }

    /// The headline numbers always; supply and the all-time low behind
    /// "Show more", so the card stays a glance. Rows without a value are left out.
    @ViewBuilder
    private var marketCard: some View {
        if let quote {
            let circulating = quote.circulatingSupply.flatMap { $0 > 0 ? $0 : nil }
            let total = quote.totalSupply.flatMap { $0 > 0 ? $0 : nil }
            let hasMore = circulating != nil || total != nil || quote.allTimeLow != nil || quote.athChangePercent != nil
            InfoCard(title: "Market") {
                if let rank = quote.rank { InfoRow("Rank") { Text(verbatim: "#\(rank)") } }
                if let cap = quote.marketCap, cap > 0 { InfoRow("Market cap") { Text(verbatim: USDPrice.compact(cap)) } }
                if let volume = quote.volume24h, volume > 0 { InfoRow("Volume (24h)") { Text(verbatim: USDPrice.compact(volume)) } }
                if let low = quote.low24h, let high = quote.high24h {
                    InfoRow("Range (24h)") { Text(verbatim: "\(USDPrice.price(low)) – \(USDPrice.price(high))") }
                }
                if let ath = quote.allTimeHigh {
                    InfoRow("All-time high") { DatedPrice(usd: ath, date: quote.allTimeHighDate) }
                }
                if showsAllStats {
                    if let change = quote.athChangePercent {
                        InfoRow("From all-time high") { Text(verbatim: Performance.text(change)) }
                    }
                    if let atl = quote.allTimeLow {
                        InfoRow("All-time low") { DatedPrice(usd: atl, date: quote.allTimeLowDate) }
                    }
                    if let circulating {
                        InfoRow("Circulating supply") { Text(verbatim: "\(Self.compactAmount(circulating)) \(token.symbol)") }
                    }
                    if let total {
                        InfoRow("Total supply") { Text(verbatim: "\(Self.compactAmount(total)) \(token.symbol)") }
                    }
                }
                if hasMore {
                    Button {
                        Haptics.tap()
                        withAnimation(reduceMotion ? nil : .snappy) { showsAllStats.toggle() }
                    } label: {
                        HStack {
                            Text(showsAllStats ? "Show less" : "Show more")
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(showsAllStats ? 180 : 0))
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.Palette.accentText)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 46)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// "86.18B", for a supply: `USDPrice.compact` without the dollar sign.
    private static func compactAmount(_ value: Double) -> String {
        let scales: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        let (scale, suffix) = scales.first { abs(value) >= $0.0 } ?? (1, "")
        let scaled = value / scale
        return scaled.formatted(.number.precision(.fractionLength(abs(scaled) < 100 ? 2 : 1)).locale(USDPrice.locale)) + suffix
    }

    private var transfersCard: some View {
        let recent = Array(app.activity.transfers.prefix(5))
        return InfoCard(title: "Recent transfers") {
            if recent.isEmpty {
                Text("No transfers yet. Received and sent USDT shows up here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                ForEach(recent) { transfer in
                    Button {
                        Haptics.tap()
                        detail = transfer
                    } label: {
                        TransferRow(transfer: transfer, myAddress: app.address ?? "", hideAmount: hideBalance,
                                    feeSun: app.activity.fees[transfer.id])
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 70)
                }
                Button {
                    Haptics.tap()
                    app.selectedTab = .activity
                } label: {
                    HStack {
                        Text("See all in Activity")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.Palette.accentText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var fuelCard: some View {
        let level = app.fuelLevel
        let sent = app.activity.fees.values
        let paid = sent.reduce(0, +)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            InfoCard(title: "Network fuel") {
                InfoRow("Transfers left") {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.caption)
                        Text(verbatim: "≈ \(app.transfersLeft)")
                    }
                    .foregroundStyle(level == .good ? Theme.Palette.textPrimary : level.color)
                }
                InfoRow("Status") {
                    Text(verbatim: level.note(transfersLeft: app.transfersLeft))
                        .foregroundStyle(level == .good ? Theme.Palette.textPrimary : level.color)
                }
                if !sent.isEmpty {
                    InfoRow("Fees paid") {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(verbatim: "\(TRX.format(sun: paid)) TRX")
                            Text("on \(sent.count) transfers")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
            Text("TRX pays the network fee for every USDT transfer, about 7–14 TRX each. Sending TRX itself isn't supported yet.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Performance

/// A period's return, for the Performance card.
private struct Performance: Identifiable {
    let range: PriceRange
    /// nil = not known (yet, or the coin's history is shorter).
    let percent: Double?
    var id: PriceRange { range }

    /// Under half a hundredth of a percent rounds to zero: shown as a plain
    /// "0.00%", never "-0.00%" (a stablecoin lives here).
    static func isFlat(_ percent: Double) -> Bool { abs(percent) < 0.005 }

    /// "+2.37%", with fewer decimals once the number is long ("+168.2%").
    static func text(_ percent: Double) -> String {
        let digits = abs(percent) >= 1000 ? 0 : abs(percent) >= 100 ? 1 : 2
        let style = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(digits)).locale(USDPrice.locale)
        guard !isFlat(percent) else { return (0.0).formatted(style) }
        return (percent / 100).formatted(style.sign(strategy: .always()))
    }
}

private extension PriceRange {
    /// The period in words, for VoiceOver ("1D" reads badly).
    var spokenTitle: String {
        switch self {
        case .day: tr("Today")
        case .week: tr("Past week")
        case .month: tr("Past month")
        case .quarter: tr("Past 3 months")
        case .year: tr("Past year")
        case .fiveYears: tr("Past 5 years")
        }
    }
}

/// One period: its short name and return. Tapping shows it on the chart.
private struct PerformanceCell: View {
    let entry: Performance
    let selected: Bool
    /// A full-width row (big text) instead of a cell in a row of five.
    let stacked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if stacked {
                    HStack {
                        Text(entry.range.caption).foregroundStyle(Theme.Palette.textSecondary)
                        Spacer(minLength: Theme.Spacing.m)
                        value
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                } else {
                    VStack(spacing: Theme.Spacing.xxs) {
                        Text(entry.range.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        value
                            .font(.footnote.weight(.semibold))
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.horizontal, 2)
                }
            }
            .lineLimit(1)
            .monospacedDigit()
            .background(selected ? Theme.Palette.surfaceRaised : .clear,
                        in: .rect(cornerRadius: stacked ? 0 : Theme.Radius.s, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.percent.map { "\(entry.range.spokenTitle), \(Performance.text($0))" }
                            ?? "\(entry.range.spokenTitle), \(tr("not available"))")
        .accessibilityHint("Shows this period on the chart")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// `PriceChange`'s colours, plus a neutral zero and a dash for no data.
    @ViewBuilder
    private var value: some View {
        if let percent = entry.percent {
            Text(verbatim: Performance.text(percent))
                .foregroundStyle(Performance.isFlat(percent) ? Theme.Palette.textSecondary
                                 : percent > 0 ? Theme.Palette.positive : Theme.Palette.danger)
                .contentTransition(.numericText())
        } else {
            Text(verbatim: "—").foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}

// MARK: - Pieces

/// A record price with the day it was set under it.
private struct DatedPrice: View {
    let usd: Double
    let date: Date?

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: USDPrice.price(usd))
            if let date {
                Text(date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

private struct InfoCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: Theme.Radius.tile)
    }
}

private struct InfoRow<Value: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let value: Value

    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: Theme.Spacing.m)
            value
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Coin") {
    let suite = "preview.coin-detail"
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let store = PriceAlertStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
    store.add(token: .trx, direction: .above, targetUSD: 0.35)
    let app = AppModel()
    app.loadDemo()
    return NavigationStack { CoinDetailView(token: .trx) }
        .environment(app)
        .environment(store)
}
#endif
