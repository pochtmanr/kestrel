import Accessibility
import Charts
import SwiftUI

/// What the Activity hero chart plots.
enum ActivityChartMode: String, CaseIterable, Identifiable {
    case balance, flow

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .balance: "Balance"
        case .flow: "Flow"
        }
    }

    var symbol: String {
        switch self {
        case .balance: "chart.xyaxis.line"
        case .flow: "chart.bar.xaxis"
        }
    }
}

/// The Activity hero chart: the balance line over the timeframe, or money in
/// (up, green) and out (down, slate) per bucket. Scrubbing writes the raw
/// x position to `selection`; the header resolves it to a point or bucket
/// with the same helpers the chart uses, so both always agree.
struct ActivityChart: View {
    let mode: ActivityChartMode
    let timeframe: Timeframe
    let series: BalanceSeries
    let buckets: [FlowBucket]
    /// Balances hidden: the chart dims and stops reporting values.
    var masked = false
    @Binding var selection: Date?

    var body: some View {
        Group {
            switch mode {
            case .balance: balanceChart
            case .flow: flowChart
            }
        }
        // Scrubbing would reveal the values the mask hides, so it's ignored.
        .chartXSelection(value: Binding(get: { masked ? nil : selection },
                                        set: { if !masked { selection = $0 } }))
        .chartLegend(.hidden)
        .opacity(masked ? 0.25 : 1)
        .accessibilityHidden(masked)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityChartDescriptor(descriptor)
    }

    // MARK: Selection

    static func point(nearest date: Date, in points: [BalancePoint]) -> BalancePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    static func bucket(containing date: Date, in buckets: [FlowBucket]) -> FlowBucket? {
        if let match = buckets.first(where: { $0.start <= date && date < $0.end }) { return match }
        // Past either edge of the plot: snap to the nearest end.
        guard let first = buckets.first else { return nil }
        return date < first.start ? first : buckets.last
    }

    // MARK: Balance

    private var balanceChart: some View {
        let points = series.points
        let domain = Self.balanceDomain(points)
        let selected = selection.flatMap { Self.point(nearest: $0, in: points) }
        let first = points.first?.date ?? .now
        let last = points.last?.date ?? .now
        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.date),
                         yStart: .value("Floor", domain.lowerBound),
                         yEnd: .value("Balance", point.usdt))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Theme.Palette.accent.opacity(0.34), Theme.Palette.accent.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", point.date), y: .value("Balance", point.usdt))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.Palette.accentText)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if let selected {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Theme.Palette.textTertiary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Date", selected.date), y: .value("Balance", selected.usdt))
                    .symbolSize(90)
                    .foregroundStyle(Theme.Palette.ember)
                    .annotation(position: .top, spacing: 10,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartCallout(title: Self.pointLabel(selected, isNow: selected.date == last),
                                     value: USDT.format(units: selected.units))
                    }
            } else if let end = points.last {
                PointMark(x: .value("Date", end.date), y: .value("Balance", end.usdt))
                    .symbolSize(48)
                    .foregroundStyle(Theme.Palette.ember)
            }
        }
        .chartXScale(domain: first ... max(last, first.addingTimeInterval(1)))
        .chartYScale(domain: domain)
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
        .chartYAxis(masked ? .hidden : .automatic)
    }

    /// Padded so a flat line sits mid-card and peaks don't touch the edge, and
    /// floored at zero: a balance never goes below it.
    static func balanceDomain(_ points: [BalancePoint]) -> ClosedRange<Double> {
        let low = points.map(\.usdt).min() ?? 0
        let high = points.map(\.usdt).max() ?? 0
        let pad = max((high - low) * 0.2, max(high, 1) * 0.05)
        return max(low - pad, 0) ... (high + pad)
    }

    // MARK: Flow

    private var flowChart: some View {
        let selected = selection.flatMap { Self.bucket(containing: $0, in: buckets) }
        let peakIn = buckets.map(\.inflowUSDT).max() ?? 0
        let peakOut = buckets.map(\.outflowUSDT).max() ?? 0
        let span = max(peakIn, peakOut, 1)
        // Headroom on both sides of zero, so a quiet direction still has a lane.
        let domain = -max(peakOut * 1.1, span * 0.15) ... max(peakIn * 1.1, span * 0.15)
        return Chart {
            ForEach(buckets) { bucket in
                let dimmed = selected.map { $0.id != bucket.id } ?? false
                BarMark(x: .value("Date", bucket.start, unit: timeframe.bucket),
                        y: .value("Amount", bucket.inflowUSDT), width: .ratio(0.62))
                    .foregroundStyle(Theme.Palette.positive.opacity(dimmed ? 0.3 : 1))
                    .clipShape(.rect(cornerRadius: Theme.Radius.xxs))
                BarMark(x: .value("Date", bucket.start, unit: timeframe.bucket),
                        y: .value("Amount", -bucket.outflowUSDT), width: .ratio(0.62))
                    .foregroundStyle(Theme.Palette.outgoing.opacity(dimmed ? 0.25 : 0.8))
                    .clipShape(.rect(cornerRadius: Theme.Radius.xxs))
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Theme.Palette.separator)
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let selected {
                RuleMark(x: .value("Date", selected.start, unit: timeframe.bucket))
                    .foregroundStyle(Theme.Palette.textTertiary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartCallout(title: Self.bucketLabel(selected, timeframe: timeframe),
                                     value: ActivityFormat.signed(selected.net))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
        .chartYAxis(masked ? .hidden : .automatic)
    }

    // MARK: Axes

    @AxisContentBuilder private var xAxis: some AxisContent {
        if mode == .flow {
            // One label per chosen bucket, under its bar. (`centered:` centres
            // between ticks, which drifts a bucket once ticks skip buckets.)
            AxisMarks(values: flowLabelDates) { _ in
                AxisValueLabel(format: Self.axisFormat(timeframe), anchor: .top)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        } else {
            AxisMarks(values: .automatic(desiredCount: timeframe == .week ? 7 : 4)) { _ in
                AxisValueLabel(format: Self.axisFormat(timeframe))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    /// Every bucket for a week, otherwise about four, counted back from the
    /// newest so the current period is always labelled.
    private var flowLabelDates: [Date] {
        let step = timeframe == .week ? 1 : max(1, Int((Double(buckets.count) / 4).rounded(.up)))
        return buckets.reversed().enumerated()
            .filter { $0.offset % step == 0 }
            .map(\.element.start)
            .reversed()
    }

    @AxisContentBuilder private var yAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                .foregroundStyle(Theme.Palette.separator)
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(ActivityFormat.compact(amount))
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private static func axisFormat(_ timeframe: Timeframe) -> Date.FormatStyle {
        switch timeframe {
        case .week: .dateTime.weekday(.abbreviated)
        case .month, .quarter: .dateTime.day().month(.abbreviated)
        case .year: .dateTime.month(.abbreviated)
        case .all: .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    // MARK: Labels

    /// "Now" for the live end of the line, otherwise the day.
    static func pointLabel(_ point: BalancePoint, isNow: Bool) -> String {
        isNow ? String(localized: "Now") : point.date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// The period one bucket covers: a day, "Week of 3 Nov", or a month.
    static func bucketLabel(_ bucket: FlowBucket, timeframe: Timeframe) -> String {
        switch timeframe.bucket {
        case .day:
            return bucket.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .weekOfYear:
            let day = bucket.start.formatted(.dateTime.day().month(.abbreviated))
            return String(localized: "Week of \(day)")
        default:
            return bucket.start.formatted(.dateTime.month(.wide).year())
        }
    }

    // MARK: Accessibility

    private var accessibilitySummary: String {
        switch mode {
        case .balance:
            let start = USDT.format(units: series.startUnits)
            let end = USDT.format(units: series.endUnits)
            return String(localized: "Balance chart, from \(start) to \(end) USDT")
        case .flow:
            let inflow = USDT.format(units: buckets.reduce(0) { $0 + $1.inflow })
            let outflow = USDT.format(units: buckets.reduce(0) { $0 + $1.outflow })
            return String(localized: "Flow chart, \(inflow) USDT in and \(outflow) USDT out")
        }
    }

    private var descriptor: ActivityChartDescriptor {
        switch mode {
        case .balance:
            let last = series.points.last?.date
            return ActivityChartDescriptor(
                title: String(localized: "Balance"),
                labels: series.points.map { Self.pointLabel($0, isNow: $0.date == last) },
                series: [(String(localized: "Balance"), series.points.map(\.usdt))],
                continuous: true)
        case .flow:
            return ActivityChartDescriptor(
                title: String(localized: "Flow"),
                labels: buckets.map { Self.bucketLabel($0, timeframe: timeframe) },
                series: [(String(localized: "In"), buckets.map(\.inflowUSDT)),
                         (String(localized: "Out"), buckets.map(\.outflowUSDT))],
                continuous: false)
        }
    }
}

/// The small label riding the scrub line.
private struct ChartCallout: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(value)
                .font(Theme.Typography.amount(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Palette.surfaceRaised, in: .rect(cornerRadius: Theme.Radius.xs, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).strokeBorder(Theme.Palette.separator))
    }
}

/// Audio Graphs data for VoiceOver: the same series the chart draws.
private struct ActivityChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let labels: [String]
    let series: [(name: String, values: [Double])]
    let continuous: Bool

    func makeChartDescriptor() -> AXChartDescriptor {
        let all = series.flatMap(\.values)
        let low = min(all.min() ?? 0, 0)
        let high = max(all.max() ?? 0, low + 1)
        // Labels can repeat (two "Nov" months in "All"), so categories are deduplicated.
        var seen = Set<String>()
        let categories = labels.filter { seen.insert($0).inserted }
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Date"), categoryOrder: categories)
        let yAxis = AXNumericDataAxisDescriptor(title: "USDT", range: low ... high, gridlinePositions: []) { value in
            "\(USDT.format(units: UInt64(max(value, 0) * 1_000_000))) USDT"
        }
        let data = series.map { entry in
            AXDataSeriesDescriptor(name: entry.name, isContinuous: continuous,
                                   dataPoints: zip(labels, entry.values).map { AXDataPoint(x: $0, y: $1) })
        }
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: data)
    }
}
