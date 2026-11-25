import Charts
import SwiftUI

/// One coin: what you hold, its price over time, the market, and what you
/// can do with it. Pushed from the Currencies screen and the home card.
struct CoinDetailView: View {
    let token: TokenKind
    @Environment(AppModel.self) private var app
    @AppStorage(SharedWallet.hideBalanceKey, store: SharedWallet.defaults) private var hideBalance = false
    @State private var range: PriceRange = .week
    @State private var points: [PricePoint] = []
    @State private var loadedRange: PriceRange?
    @State private var chartFailed = false
    @State private var selection: Date?
    @State private var detail: TokenTransfer?

    private var holding: Holding { app.holding(of: token) }
    private var price: TokenPrice? { app.prices[token] }
    private var quote: MarketQuote? { app.markets[token] }
    private var selectedPoint: PricePoint? { selection.flatMap { points.nearest(to: $0) } }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header
                actions
                priceSection
                positionCard
                if quote != nil { marketCard }
                switch token {
                case .usdt: transfersCard
                case .trx: fuelCard
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle(token.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            async let prices: Void = app.refreshPrices()
            await app.refresh()
            await prices
            await loadChart()
        }
        .task(id: range) { await loadChart() }
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
        if loadedRange != range, let cached = app.cachedChart(for: token, range: range) {
            points = cached
            loadedRange = range
        }
        do {
            let fresh = try await app.chart(for: token, range: range)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                points = fresh
                loadedRange = range
                chartFailed = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            if loadedRange != range { chartFailed = true }
        }
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
            priceLabel
            PriceChart(points: loadedRange == range ? points : [], range: range,
                       dimmed: loadedRange != range && !points.isEmpty, failed: chartFailed,
                       selection: $selection) {
                chartFailed = false
                Task { await loadChart() }
            }
            .frame(height: 200)
            PillPicker(selection: $range, options: PriceRange.allCases) { $0.title }
                .onChange(of: range) { selection = nil }
        }
        .padding(Theme.Spacing.l)
        .surface(cornerRadius: Theme.Radius.tile)
    }

    @ViewBuilder
    private var priceLabel: some View {
        let shown = selectedPoint?.usd ?? price?.usd
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: shown.map(USDPrice.price) ?? "—")
                .font(Theme.Typography.amount(28, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            HStack(spacing: Theme.Spacing.xs) {
                if let point = selectedPoint {
                    Text(point.date, format: range == .day ? .dateTime.hour().minute() : .dateTime.day().month().year())
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
        return loadedRange == range ? points.changePercent : nil
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

    @ViewBuilder
    private var marketCard: some View {
        if let quote {
            InfoCard(title: "Market") {
                if let cap = quote.marketCap, cap > 0 { InfoRow("Market cap") { Text(verbatim: USDPrice.compact(cap)) } }
                if let volume = quote.volume24h, volume > 0 { InfoRow("Volume (24h)") { Text(verbatim: USDPrice.compact(volume)) } }
                if let low = quote.low24h, let high = quote.high24h {
                    InfoRow("Range (24h)") { Text(verbatim: "\(USDPrice.price(low)) – \(USDPrice.price(high))") }
                }
                if let change = quote.change7d { InfoRow("Change (7d)") { PriceChange(percent: change) } }
                if let ath = quote.allTimeHigh {
                    InfoRow("All-time high") {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(verbatim: USDPrice.price(ath))
                            if let date = quote.allTimeHighDate {
                                Text(date, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
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
            Text("TRX pays the network fee for every USDT transfer, about 13–14 TRX each. Sending TRX itself isn't supported yet.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Chart

/// Price over the range: a line with a soft fill, green when the range ends
/// up, red when down. Dragging writes the date under the finger to `selection`.
private struct PriceChart: View {
    let points: [PricePoint]
    let range: PriceRange
    /// The previous range's line stays faintly while the new one loads.
    let dimmed: Bool
    let failed: Bool
    @Binding var selection: Date?
    let retry: () -> Void

    private var rising: Bool { (points.changePercent ?? 0) >= 0 }
    private var tint: Color { rising ? Theme.Palette.positive : Theme.Palette.danger }
    private var selected: PricePoint? { selection.flatMap { points.nearest(to: $0) } }

    var body: some View {
        if points.count > 1, let low = points.map(\.usd).min(), let high = points.map(\.usd).max() {
            let pad = max((high - low) * 0.15, high * 0.0002)
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Date", point.date), yStart: .value("Low", low - pad), yEnd: .value("Price", point.usd))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.date), y: .value("Price", point.usd))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(tint)
                }
                if let selected {
                    RuleMark(x: .value("Selected", selected.date))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    PointMark(x: .value("Selected", selected.date), y: .value("Price", selected.usd))
                        .symbolSize(70)
                        .foregroundStyle(tint)
                }
            }
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.Palette.separator)
                    AxisValueLabel {
                        if let usd = value.as(Double.self) {
                            Text(verbatim: USDPrice.price(usd)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
            .chartXSelection(value: $selection)
            .sensoryFeedback(.selection, trigger: selected?.date)
            .opacity(dimmed ? 0.35 : 1)
            .accessibilityLabel(accessibilitySummary(low: low, high: high))
            .accessibilityChartDescriptor(PriceChartDescriptor(points: points))
        } else if failed {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: "chart.line.downtrend.xyaxis").font(.title2).foregroundStyle(Theme.Palette.textTertiary)
                Text("Price history unavailable").font(.subheadline).foregroundStyle(Theme.Palette.textSecondary)
                Button("Try again", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accentText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func accessibilitySummary(low: Double, high: Double) -> String {
        let change = points.changePercent.map(USDPrice.percent) ?? ""
        return String(localized: "Price chart. Low \(USDPrice.price(low)), high \(USDPrice.price(high)), change \(change)")
    }
}

private struct PriceChartDescriptor: AXChartDescriptorRepresentable {
    let points: [PricePoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let low = points.map(\.usd).min() ?? 0
        let high = points.map(\.usd).max() ?? 1
        let start = points.first?.date ?? .now
        let end = points.last?.date ?? .now
        let x = AXNumericDataAxisDescriptor(title: String(localized: "Date"),
                                            range: start.timeIntervalSince1970...max(end.timeIntervalSince1970, start.timeIntervalSince1970 + 1),
                                            gridlinePositions: []) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) }
        let y = AXNumericDataAxisDescriptor(title: String(localized: "Price"), range: low...max(high, low + 0.0001),
                                            gridlinePositions: []) { USDPrice.price($0) }
        let series = AXDataSeriesDescriptor(name: String(localized: "Price"), isContinuous: true,
                                            dataPoints: points.map { .init(x: $0.date.timeIntervalSince1970, y: $0.usd) })
        return AXChartDescriptor(title: String(localized: "Price history"), summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}

// MARK: - Pieces

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
