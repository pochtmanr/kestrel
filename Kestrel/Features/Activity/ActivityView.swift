import SwiftUI

/// The Activity tab, one scrolling screen: a chart hero for the chosen
/// timeframe, insight tiles, the top counterparties, then every transfer by
/// day, searchable and filterable.
struct ActivityView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SharedWallet.hideBalanceKey, store: SharedWallet.defaults) private var hideBalance = false
    @State private var timeframe: Timeframe = .month
    @State private var mode: ActivityChartMode = .balance
    @State private var query = TransferQuery()
    @State private var detail: TokenTransfer?
    @State private var showFilters = false

    private static let resultsID = "results"

    var body: some View {
        let snapshot = makeSnapshot()
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        ActivityHeader(timeframe: $timeframe, mode: $mode, series: snapshot.series,
                                       buckets: snapshot.buckets, insights: snapshot.insights,
                                       masked: hideBalance, coverage: snapshot.coverage) {
                            Task { await app.activity.ensureCoverage(since: coverageTarget(start: snapshot.start)) }
                        }
                    }
                    .cardRow()

                    if snapshot.hasHistory {
                        Section { insightsGrid(snapshot) }
                            .cardRow()

                        if !snapshot.insights.topCounterparties.isEmpty {
                            Section { counterpartiesCard(snapshot.insights.topCounterparties, proxy: proxy) }
                                .cardRow()
                        }

                        Section {
                            resultsHeader(snapshot)
                                .id(Self.resultsID)
                        }
                        .cardRow()

                        if snapshot.groups.isEmpty {
                            Section { noResults }
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(snapshot.groups) { group in
                                Section(group.title) {
                                    ForEach(group.items) { transfer in
                                        Button { detail = transfer } label: {
                                            TransferRow(transfer: transfer, myAddress: snapshot.me, hideAmount: hideBalance,
                                                        feeSun: app.activity.fees[transfer.id])
                                                .contentShape(.rect)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .listRowBackground(Theme.Palette.surface)
                            }
                        }
                    } else {
                        Section {
                            ContentUnavailableView("No activity yet", systemImage: "clock",
                                                   description: Text("Transfers show up here"))
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listSectionSpacing(Theme.Spacing.l)
                .scrollContentBackground(.hidden)
                .background(Theme.Palette.background)
                .navigationTitle("Activity")
                .searchable(text: $query.text, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text("Address, amount or tx id"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showFilters = true } label: {
                            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel(hasFilters ? "Filters, on" : "Filters")
                    }
                }
                .refreshable {
                    await app.refresh()
                    await app.activity.ensureCoverage(since: coverageTarget(start: snapshot.start))
                }
                .animation(.snappy, value: query)
                .animation(.snappy, value: timeframe)
            }
            .task(id: timeframe) { await loadCoverage() }
            .sheet(isPresented: $showFilters) {
                ActivityFilterSheet(query: $query)
                    .presentationDetents([.medium, .large])
            }
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
    }

    // MARK: Data

    /// Everything the screen shows, computed once per render. The header keeps
    /// its scrub state to itself, so dragging across the chart doesn't rebuild this.
    private struct Snapshot {
        let me: String
        let start: Date?
        let series: BalanceSeries
        let buckets: [FlowBucket]
        let insights: ActivityInsights
        let inCount: Int
        let outCount: Int
        let hasHistory: Bool
        let resultCount: Int
        let groups: [DayGroup]
        let coverage: ActivityCoverage
    }

    struct DayGroup: Identifiable {
        let id: Date
        let title: String
        var items: [TokenTransfer]
    }

    private func makeSnapshot() -> Snapshot {
        let calendar = Calendar.current
        let now = Date.now
        let me = app.address ?? ""
        let activity = app.activity
        // The home screen's 25 stand in until the full history first arrives.
        let transfers = activity.transfers.isEmpty ? app.history : activity.transfers
        let start = timeframe.start(now: now, calendar: calendar, earliest: transfers.last?.date)
        let inRange = start.map { since in transfers.filter { $0.date >= since } } ?? transfers

        // A search or filter looks through all cached history: someone hunting
        // for one payment shouldn't first have to guess its timeframe.
        let results = query.isActive ? transfers.filter { query.matches($0, me: me, calendar: calendar) } : inRange
        let outCount = inRange.reduce(0) { $0 + ($1.from == me ? 1 : 0) }

        let coverage: ActivityCoverage
        if activity.isComplete(since: coverageTarget(start: start)) {
            coverage = .complete
        } else if activity.isLoading {
            coverage = .loading
        } else {
            coverage = .partial(since: activity.transfers.isEmpty ? nil : activity.coveredSince)
        }

        return Snapshot(
            me: me, start: start,
            series: ActivityAnalytics.balanceSeries(current: app.usdtUnits, transfers: transfers, me: me,
                                                    timeframe: timeframe, now: now, calendar: calendar),
            buckets: ActivityAnalytics.flowBuckets(transfers: transfers, me: me, timeframe: timeframe, now: now, calendar: calendar),
            insights: ActivityAnalytics.insights(transfers: inRange, fees: activity.fees, me: me, since: nil),
            inCount: inRange.count - outCount, outCount: outCount,
            hasHistory: !transfers.isEmpty,
            resultCount: results.count,
            groups: Self.groupByDay(results, calendar: calendar),
            coverage: coverage
        )
    }

    /// "All" asks for the very start; a fixed timeframe for its first day.
    private func coverageTarget(start: Date?) -> Date? {
        timeframe == .all ? nil : start
    }

    private func loadCoverage() async {
        // A refresh may be mid-sync, and ensureCoverage returns at once while
        // the store is busy, so wait for it (a few seconds at most).
        var waits = 0
        while app.activity.isLoading, waits < 40, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            waits += 1
        }
        guard !Task.isCancelled else { return }
        let start = timeframe.start(now: .now, calendar: .current, earliest: app.activity.transfers.last?.date)
        await app.activity.ensureCoverage(since: coverageTarget(start: start))
    }

    private static func groupByDay(_ transfers: [TokenTransfer], calendar: Calendar) -> [DayGroup] {
        var result: [DayGroup] = []
        for transfer in transfers {
            let day = calendar.startOfDay(for: transfer.date)
            if result.last?.id == day {
                result[result.count - 1].items.append(transfer)
                continue
            }
            let title: String
            if calendar.isDateInToday(day) { title = String(localized: "Today") }
            else if calendar.isDateInYesterday(day) { title = String(localized: "Yesterday") }
            else { title = day.formatted(date: .abbreviated, time: .omitted) }
            result.append(DayGroup(id: day, title: title, items: [transfer]))
        }
        return result
    }

    /// Filters other than the search text (those get chips and the filled icon).
    private var hasFilters: Bool {
        var filters = query
        filters.text = ""
        return filters.isActive
    }

    // MARK: Insights

    private func insightsGrid(_ snapshot: Snapshot) -> some View {
        let insights = snapshot.insights
        let mask = "••••"
        let largest = [insights.largestIn, insights.largestOut].compactMap { $0 }.max { $0.units < $1.units }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Insights").font(.title3.weight(.bold))
                Spacer()
                Text(timeframe.periodTitle).font(.subheadline).foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.xs)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible())],
                      spacing: Theme.Spacing.m) {
                StatTile(title: "In", symbol: "arrow.down.left", tint: Theme.Palette.positive,
                         value: hideBalance ? mask : "+\(USDT.format(units: insights.inflow))",
                         valueColor: Theme.Palette.positive,
                         detail: String(localized: "\(snapshot.inCount) received"))
                StatTile(title: "Out", symbol: "arrow.up.right", tint: Theme.Palette.outgoing,
                         value: hideBalance ? mask : "−\(USDT.format(units: insights.outflow))",
                         detail: String(localized: "\(snapshot.outCount) sent"))
                StatTile(title: "Net", symbol: "plusminus", tint: Theme.Palette.accentText,
                         value: hideBalance ? mask : ActivityFormat.signed(insights.net),
                         valueColor: insights.net > 0 ? Theme.Palette.positive : Theme.Palette.textPrimary,
                         detail: String(localized: "In minus out"))
                StatTile(title: "Network fees", symbol: "flame", tint: Theme.Palette.ember,
                         value: hideBalance ? mask : "\(TRX.format(sun: insights.feesSun)) TRX",
                         detail: feeDetail(insights.feesSun))
                StatTile(title: "Transfers", symbol: "arrow.left.arrow.right", tint: Theme.Palette.accentText,
                         value: "\(insights.count)",
                         detail: insights.count == 0 || hideBalance ? nil
                             : String(localized: "Avg \(USDT.format(units: insights.averageUnits))"))
                Button {
                    if let largest { detail = largest }
                } label: {
                    StatTile(title: "Largest", symbol: "arrow.up.and.down", tint: Theme.Palette.warning,
                             value: largest.map { hideBalance ? mask : "\($0.from == snapshot.me ? "−" : "+")\(USDT.format(units: $0.units))" } ?? "—",
                             valueColor: largest.map { $0.from == snapshot.me ? Theme.Palette.textPrimary : Theme.Palette.positive } ?? Theme.Palette.textTertiary,
                             detail: largest.map { transfer in
                                 let day = transfer.date.formatted(.dateTime.day().month(.abbreviated))
                                 return transfer.from == snapshot.me ? String(localized: "Sent · \(day)") : String(localized: "Received · \(day)")
                             },
                             showsChevron: largest != nil)
                }
                .buttonStyle(CardPressStyle())
                .disabled(largest == nil)
            }
        }
    }

    private func feeDetail(_ sun: Int64) -> String? {
        guard !hideBalance, sun > 0, let price = app.prices[.trx]?.usd else { return nil }
        return "≈ \(ActivityFormat.usd(Double(sun) / 1_000_000 * price))"
    }

    // MARK: Counterparties

    private func counterpartiesCard(_ parties: [Counterparty], proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Top counterparties")
                .font(.headline)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xs)
            ForEach(Array(parties.enumerated()), id: \.element.id) { index, party in
                if index > 0 { Divider().padding(.leading, 64) }
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) {
                        query.counterparty = query.counterparty == party.address ? nil : party.address
                    }
                    if query.counterparty != nil {
                        withAnimation(.snappy) { proxy.scrollTo(Self.resultsID, anchor: .top) }
                    }
                } label: {
                    counterpartyRow(party, rank: index + 1, selected: query.counterparty == party.address)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, Theme.Spacing.xs)
        .surface(cornerRadius: Theme.Radius.card)
    }

    private func counterpartyRow(_ party: Counterparty, rank: Int, selected: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text("\(rank)")
                .font(Theme.Typography.amount(15, weight: .bold))
                .foregroundStyle(Theme.Palette.accentText)
                .frame(width: 36, height: 36)
                .background(Theme.Palette.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(party.address.shortAddress)
                    .font(.body.weight(.medium).monospaced())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("^[\(party.count) transfer](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(hideBalance ? "••••" : ActivityFormat.signed(party.net))
                    .font(Theme.Typography.amount(16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(party.net > 0 ? Theme.Palette.positive : Theme.Palette.textPrimary)
                Text("Net").font(.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Theme.Palette.accentText : Theme.Palette.textTertiary)
                .frame(width: 20)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(selected ? Theme.Palette.accent.opacity(0.08) : .clear)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(selected ? "Shows all transfers" : "Shows only transfers with this address")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: List

    private func resultsHeader(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transfers").font(.title3.weight(.bold))
                Spacer()
                Group {
                    if query.isActive {
                        Text("\(snapshot.resultCount) found in all history")
                    } else {
                        Text(timeframe.periodTitle)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
                .contentTransition(.numericText())
            }
            .padding(.horizontal, Theme.Spacing.s)

            let chips = filterChips
            if !chips.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(chips) { chip in
                            FilterChipView(chip: chip)
                        }
                        if chips.count > 1 {
                            Button("Clear all") { withAnimation(.snappy) { clearFilters() } }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.Palette.accentText)
                                .padding(.leading, Theme.Spacing.xxs)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder
    private var noResults: some View {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasFilters {
            ContentUnavailableView {
                Label("No transfers match", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try a wider amount or date range.")
            } actions: {
                Button("Clear filters") { withAnimation(.snappy) { clearFilters() } }
                    .buttonStyle(.bordered)
            }
        } else if !text.isEmpty {
            ContentUnavailableView.search(text: text)
        } else {
            ContentUnavailableView("Nothing in this period", systemImage: "calendar",
                                   description: Text("Pick a longer timeframe to see older transfers."))
        }
    }

    private func clearFilters() {
        let text = query.text
        query = TransferQuery()
        query.text = text
    }

    private var filterChips: [FilterChip] {
        var chips: [FilterChip] = []
        switch query.direction {
        case .all: break
        case .incoming: chips.append(FilterChip(id: "direction", label: String(localized: "Received only")) { query.direction = .all })
        case .outgoing: chips.append(FilterChip(id: "direction", label: String(localized: "Sent only")) { query.direction = .all })
        }
        let low = query.minUnits.map { USDT.format(units: $0) }
        let high = query.maxUnits.map { USDT.format(units: $0) }
        if low != nil || high != nil {
            let label = switch (low, high) {
            case let (low?, high?): String(localized: "\(low)–\(high) USDT")
            case let (low?, nil): String(localized: "≥ \(low) USDT")
            case let (nil, high?): String(localized: "≤ \(high) USDT")
            default: ""
            }
            chips.append(FilterChip(id: "amount", label: label) {
                query.minUnits = nil
                query.maxUnits = nil
            })
        }
        let from = query.from.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) }
        let to = query.to.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) }
        if from != nil || to != nil {
            let label = switch (from, to) {
            case let (from?, to?): "\(from) – \(to)"
            case let (from?, nil): String(localized: "Since \(from)")
            case let (nil, to?): String(localized: "Until \(to)")
            default: ""
            }
            chips.append(FilterChip(id: "dates", label: label) {
                query.from = nil
                query.to = nil
            })
        }
        if let counterparty = query.counterparty {
            chips.append(FilterChip(id: "counterparty", label: String(localized: "With \(counterparty.shortAddress)"), monospaced: true) {
                query.counterparty = nil
            })
        }
        return chips
    }
}

// MARK: - Header

/// Whether the loaded history reaches back to the timeframe's start.
enum ActivityCoverage: Equatable {
    case complete
    case loading
    /// Older history isn't loaded; `since` is how far it goes, nil if unknown.
    case partial(since: Date?)
}

/// The hero card: mode switch, the big figure, the chart and the timeframe
/// pills. It owns the scrub position, so a drag redraws only this card.
private struct ActivityHeader: View {
    @Binding var timeframe: Timeframe
    @Binding var mode: ActivityChartMode
    let series: BalanceSeries
    let buckets: [FlowBucket]
    let insights: ActivityInsights
    let masked: Bool
    let coverage: ActivityCoverage
    let onLoadMore: () -> Void

    @State private var selection: Date?

    private var selectedPoint: BalancePoint? {
        guard mode == .balance, !masked, let selection else { return nil }
        return ActivityChart.point(nearest: selection, in: series.points)
    }

    private var selectedBucket: FlowBucket? {
        guard mode == .flow, !masked, let selection else { return nil }
        return ActivityChart.bucket(containing: selection, in: buckets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ModeSwitch(selection: $mode)
            figure
            ActivityChart(mode: mode, timeframe: timeframe, series: series, buckets: buckets,
                          masked: masked, selection: $selection)
                .frame(height: 190)
                .id(mode)
                .transition(.opacity)
            TimeframePicker(selection: $timeframe)
            coverageNote
        }
        .padding(Theme.Spacing.l)
        .padding(.top, Theme.Spacing.xxs)
        .surface(cornerRadius: Theme.Radius.card)
        .sensoryFeedback(.selection, trigger: selectedPoint?.date ?? selectedBucket?.start)
        .animation(.smooth(duration: 0.35), value: mode)
        .animation(.smooth(duration: 0.35), value: timeframe)
        .onChange(of: mode) { selection = nil }
        .onChange(of: timeframe) { selection = nil }
        .onChange(of: masked) { selection = nil }
    }

    // MARK: Figure

    @ViewBuilder
    private var figure: some View {
        switch mode {
        case .balance: balanceFigure
        case .flow: flowFigure
        }
    }

    private var balanceFigure: some View {
        let point = selectedPoint
        let units = point?.units ?? series.endUnits
        let change = Int64(clamping: units) - Int64(clamping: series.startUnits)
        let percent = series.startUnits == 0 ? nil : Double(change) / Double(series.startUnits)
        let caption = point.map { ActivityChart.pointLabel($0, isNow: $0.date == series.points.last?.date) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            bigAmount(USDT.format(units: units), value: Double(units))
            HStack(spacing: Theme.Spacing.xs) {
                if !masked {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))
                    Text(changeText(change, percent: percent))
                        .contentTransition(.numericText(value: Double(change)))
                }
                periodLabel(caption)
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(change > 0 ? Theme.Palette.positive : Theme.Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var flowFigure: some View {
        let bucket = selectedBucket
        let net = bucket?.net ?? insights.net
        let inflow = bucket?.inflow ?? insights.inflow
        let outflow = bucket?.outflow ?? insights.outflow
        let caption = bucket.map { ActivityChart.bucketLabel($0, timeframe: timeframe) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            bigAmount(ActivityFormat.signed(net), value: Double(net),
                      color: net > 0 && !masked ? Theme.Palette.positive : Theme.Palette.textPrimary)
            HStack(spacing: Theme.Spacing.m) {
                if !masked {
                    Label { Text(verbatim: "+\(USDT.format(units: inflow))") } icon: {
                        Circle().fill(Theme.Palette.positive).frame(width: 7, height: 7)
                    }
                    .foregroundStyle(Theme.Palette.positive)
                    Label { Text(verbatim: "−\(USDT.format(units: outflow))") } icon: {
                        Circle().fill(Theme.Palette.outgoing).frame(width: 7, height: 7)
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
                periodLabel(caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .labelStyle(DotLabelStyle())
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private func bigAmount(_ text: String, value: Double, color: Color = Theme.Palette.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text(masked ? "••••" : text)
                .font(Theme.Typography.amount(40, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText(value: value))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: "USDT")
                .font(Theme.Typography.amount(17, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .animation(.snappy(duration: 0.25), value: text)
    }

    /// The scrubbed date when there is one, otherwise the timeframe.
    @ViewBuilder
    private func periodLabel(_ caption: String?) -> some View {
        Group {
            if let caption {
                Text(verbatim: masked ? caption : "· \(caption)")
            } else if masked {
                Text(timeframe.periodTitle)
            } else {
                Text("· \(Text(timeframe.periodTitle))")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.Palette.textSecondary)
    }

    private func changeText(_ change: Int64, percent: Double?) -> String {
        let amount = ActivityFormat.signed(change)
        guard let percent else { return amount }
        return "\(amount) (\(ActivityFormat.percent(percent)))"
    }

    // MARK: Coverage

    @ViewBuilder
    private var coverageNote: some View {
        switch coverage {
        case .complete:
            EmptyView()
        case .loading:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Loading older history…")
            }
            .font(.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity)
        case .partial(let since):
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "clock.arrow.circlepath")
                Group {
                    if let since {
                        Text("Showing history since \(since.formatted(.dateTime.day().month(.abbreviated).year()))")
                    } else {
                        Text("Showing recent history only")
                    }
                }
                .lineLimit(2)
                Spacer(minLength: Theme.Spacing.s)
                Button("Load more", action: onLoadMore)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accentText)
            }
            .font(.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

/// The 7D…All pills: an accent capsule slides to the chosen one.
private struct TimeframePicker: View {
    @Binding var selection: Timeframe
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Timeframe.allCases) { timeframe in
                let selected = timeframe == selection
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = timeframe }
                } label: {
                    Text(timeframe.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.white : Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.Palette.accent)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.Palette.surfaceRaised, in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Balance or Flow: two small chips, the chosen one tinted.
private struct ModeSwitch: View {
    @Binding var selection: ActivityChartMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(ActivityChartMode.allCases) { mode in
                let selected = mode == selection
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = mode }
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selected ? Theme.Palette.accentText : Theme.Palette.textTertiary)
                        .padding(.horizontal, Theme.Spacing.m)
                        .frame(minHeight: 30)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.Palette.accent.opacity(0.16))
                                    .matchedGeometryEffect(id: "mode", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A coloured dot and its amount, tight together.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Pieces

private struct StatTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let value: String
    var valueColor: Color = Theme.Palette.textPrimary
    var detail: String?
    var showsChevron = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.14), in: .circle)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Text(value)
                .font(Theme.Typography.amount(20, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .surface(cornerRadius: Theme.Radius.l)
        .accessibilityElement(children: .combine)
    }
}

private struct FilterChip: Identifiable {
    let id: String
    let label: String
    var monospaced = false
    let remove: () -> Void
}

private struct FilterChipView: View {
    let chip: FilterChip

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { chip.remove() }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(chip.label)
                    .font(chip.monospaced ? .subheadline.weight(.medium).monospaced() : .subheadline.weight(.medium))
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Theme.Palette.accentText)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(Theme.Palette.accent.opacity(0.14), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove filter: \(chip.label)"))
    }
}

private extension View {
    /// A list row that draws its own card (or nothing): no inset, fill or hairline.
    func cardRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension Timeframe {
    /// The timeframe in words, beside totals for it.
    var periodTitle: LocalizedStringKey {
        switch self {
        case .week: "Past 7 days"
        case .month: "Past 30 days"
        case .quarter: "Past 3 months"
        case .year: "Past year"
        case .all: "All time"
        }
    }
}

/// Amount strings shared by the Activity screen and its chart.
enum ActivityFormat {
    /// "+1,234.56", "−80.00" or "0.00" (a true minus sign, like the rows).
    static func signed(_ units: Int64) -> String {
        let sign = units > 0 ? "+" : units < 0 ? "−" : ""
        return sign + USDT.format(units: units.magnitude)
    }

    /// A fraction as "+25.3%", in the same fixed separators and true minus
    /// as the amounts beside it, whatever the device region.
    static func percent(_ fraction: Double) -> String {
        let digits = (abs(fraction) * 100).formatted(.number.precision(.fractionLength(1)).locale(fixed))
        let sign = fraction > 0 ? "+" : fraction < 0 ? "−" : ""
        return "\(sign)\(digits)%"
    }

    /// Axis labels: "2.5K".
    static func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1 ... 3)))
    }

    /// Dollars in the fixed "$1,234.56" style the rest of the app uses.
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(fixed))
    }

    private static let fixed = Locale(identifier: "en_US")
}
