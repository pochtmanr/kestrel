import Accessibility
import Charts
import SwiftUI

/// Price over the range: a line with a soft fill, green when the range ends
/// up, red when down. Dragging writes the date under the finger to
/// `selection`. The caller sets the height (or lets it fill).
///
/// Optional extras: markers on the highest and lowest point, and volume bars
/// in a band under the line. The bars live in the same chart as the line, so
/// they share its x-axis and the scrub rule crosses both.
struct PriceChartView: View {
    let points: [PricePoint]
    /// The range `points` belong to: it decides what the volume means.
    let range: PriceRange
    var showsVolume = false
    var showsExtremes = false
    /// A stale line (the previous range) shown faintly while the new one loads.
    var dimmed = false
    var failed = false
    @Binding var selection: Date?
    let retry: () -> Void

    private var rising: Bool { (points.changePercent ?? 0) >= 0 }
    private var tint: Color { rising ? Theme.Palette.positive : Theme.Palette.danger }
    private var selected: PricePoint? { dimmed ? nil : selection.flatMap { points.nearest(to: $0) } }

    var body: some View {
        let buckets = showsVolume ? points.volumeBuckets() : []
        let active = selected.flatMap { buckets.bucket(containing: $0.date) }
        VStack(spacing: Theme.Spacing.xs) {
            plot(buckets: buckets, active: active)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsVolume {
                volumeCaption(hasVolume: !buckets.isEmpty, active: active)
            }
        }
    }

    // MARK: Plot

    @ViewBuilder
    private func plot(buckets: [VolumeBucket], active: VolumeBucket?) -> some View {
        if points.count > 1, let low = points.map(\.usd).min(), let high = points.map(\.usd).max(),
           let first = points.first?.date, let last = points.last?.date {
            // Room above and below the line; a little more when labels sit there.
            let pad = max((high - low) * (showsExtremes ? 0.2 : 0.15), high * 0.0002)
            let priceFloor = low - pad
            let ceiling = high + pad
            // The volume band hangs under the price band, in price units.
            let span = ceiling - priceFloor
            let band = buckets.isEmpty ? 0 : span * 0.22
            let floor = buckets.isEmpty ? priceFloor : priceFloor - span * 0.05 - band
            let peak = max(buckets.map(\.usd).max() ?? 0, .leastNonzeroMagnitude)
            let extremes = showsExtremes && selected == nil && high > low ? Extremes(points) : nil
            let seconds = max(last.timeIntervalSince(first), 1)
            Chart {
                ForEach(buckets) { bucket in
                    let inset = bucket.end.timeIntervalSince(bucket.start) * 0.14
                    RectangleMark(xStart: .value("Start", bucket.start.addingTimeInterval(inset)),
                                  xEnd: .value("End", bucket.end.addingTimeInterval(-inset)),
                                  yStart: .value("Floor", floor),
                                  // A sliver even for a quiet bucket, so it reads as "little", not "missing".
                                  yEnd: .value("Volume", floor + band * max(bucket.usd / peak, 0.04)))
                        .foregroundStyle(Theme.Palette.textTertiary.opacity(active == nil ? 0.45 : bucket.id == active?.id ? 0.95 : 0.25))
                }
                ForEach(points) { point in
                    AreaMark(x: .value("Date", point.date), yStart: .value("Low", priceFloor), yEnd: .value("Price", point.usd))
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
                } else if let extremes {
                    // Hidden while scrubbing: the scrub readout owns the chart then.
                    extremeMark(extremes.high, above: true, fraction: extremes.high.date.timeIntervalSince(first) / seconds)
                    extremeMark(extremes.low, above: false, fraction: extremes.low.date.timeIntervalSince(first) / seconds)
                }
            }
            .chartXScale(domain: first ... max(last, first.addingTimeInterval(1)))
            .chartYScale(domain: floor ... ceiling)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: buckets.isEmpty ? 3 : 4)) { value in
                    // No price labels beside the volume band: its height isn't a price.
                    if let usd = value.as(Double.self), usd >= priceFloor {
                        AxisGridLine().foregroundStyle(Theme.Palette.separator)
                        AxisValueLabel {
                            Text(verbatim: USDPrice.price(usd)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $selection)
            .sensoryFeedback(.selection, trigger: selected?.date)
            .opacity(dimmed ? 0.35 : 1)
            // The faint line is another range's: nothing on it to read off.
            .allowsHitTesting(!dimmed)
            .overlay { if dimmed { ProgressView() } }
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

    /// A dot on the highest or lowest point with its price. The label leans
    /// away from the nearer side edge and is kept inside the plot.
    private func extremeMark(_ point: PricePoint, above: Bool, fraction: Double) -> some ChartContent {
        let position: AnnotationPosition = switch (above, fraction) {
        case (true, ..<0.15): .topTrailing
        case (true, 0.85...): .topLeading
        case (true, _): .top
        case (false, ..<0.15): .bottomTrailing
        case (false, 0.85...): .bottomLeading
        case (false, _): .bottom
        }
        return PointMark(x: .value("Date", point.date), y: .value("Price", point.usd))
            .symbolSize(26)
            .foregroundStyle(tint)
            .annotation(position: position, spacing: 3,
                        overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                Text(verbatim: USDPrice.price(point.usd))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
    }

    // MARK: Volume caption

    /// Says what the bars are, and the scrubbed bucket's value. Its height is
    /// kept even without volume data, so the chart doesn't jump when it arrives.
    private func volumeCaption(hasVolume: Bool, active: VolumeBucket?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(range.volumeCaption)
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer(minLength: Theme.Spacing.s)
            if let active {
                Text(verbatim: USDPrice.compact(active.usd))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .contentTransition(.numericText())
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .opacity(hasVolume && !dimmed ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!hasVolume || dimmed)
    }

    private func accessibilitySummary(low: Double, high: Double) -> String {
        let change = points.changePercent.map(USDPrice.percent) ?? ""
        return tr("Price chart. Low \(USDPrice.price(low)), high \(USDPrice.price(high)), change \(change)")
    }
}

private struct Extremes {
    let high: PricePoint
    let low: PricePoint

    init?(_ points: [PricePoint]) {
        guard let high = points.max(by: { $0.usd < $1.usd }), let low = points.min(by: { $0.usd < $1.usd }) else { return nil }
        self.high = high
        self.low = low
    }
}

private struct PriceChartDescriptor: AXChartDescriptorRepresentable {
    let points: [PricePoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let low = points.map(\.usd).min() ?? 0
        let high = points.map(\.usd).max() ?? 1
        let start = points.first?.date ?? .now
        let end = points.last?.date ?? .now
        let x = AXNumericDataAxisDescriptor(title: tr("Date"),
                                            range: start.timeIntervalSince1970...max(end.timeIntervalSince1970, start.timeIntervalSince1970 + 1),
                                            gridlinePositions: []) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) }
        let y = AXNumericDataAxisDescriptor(title: tr("Price"), range: low...max(high, low + 0.0001),
                                            gridlinePositions: []) { USDPrice.price($0) }
        let series = AXDataSeriesDescriptor(name: tr("Price"), isContinuous: true,
                                            dataPoints: points.map { .init(x: $0.date.timeIntervalSince1970, y: $0.usd) })
        return AXChartDescriptor(title: tr("Price history"), summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}

// MARK: - Volume

/// One volume bar: the average of the points' volumes in a slice of the range.
struct VolumeBucket: Identifiable, Equatable {
    let start: Date
    let end: Date
    let usd: Double
    var id: Date { start }
}

extension PriceRange {
    /// What a point's volume is on this range. Up to a year it's CoinGecko's
    /// trailing 24 hours across all markets; the five-year range is Kraken's
    /// weekly candles, one exchange only and so far smaller. Never label the
    /// two alike.
    var volumeCaption: LocalizedStringKey {
        self == .fiveYears ? "Weekly volume on Kraken" : "Volume (24h)"
    }

    /// The same distinction for an average over the range.
    var averageVolumeCaption: LocalizedStringKey {
        self == .fiveYears ? "Avg. weekly volume" : "Avg. volume (24h)"
    }
}

extension Array where Element == PricePoint {
    /// The range cut into at most `limit` equal slices of time, each with the
    /// average volume of its points. An average, not a sum: every point's
    /// volume already covers a period (24 hours, or a week), so the bar keeps
    /// the meaning its caption gives. Slices without volume are left out.
    func volumeBuckets(limit: Int = 60) -> [VolumeBucket] {
        guard let first = first?.date, let last = last?.date, last > first, limit > 0 else { return [] }
        let slices = Swift.min(limit, count)
        let width = last.timeIntervalSince(first) / Double(slices)
        var sums = [Double](repeating: 0, count: slices)
        var seen = [Int](repeating: 0, count: slices)
        for point in self {
            guard let volume = point.volume, volume.isFinite, volume >= 0 else { continue }
            let index = Swift.min(slices - 1, Swift.max(0, Int(point.date.timeIntervalSince(first) / width)))
            sums[index] += volume
            seen[index] += 1
        }
        return (0..<slices).compactMap { index in
            guard seen[index] > 0 else { return nil }
            return VolumeBucket(start: first.addingTimeInterval(width * Double(index)),
                                end: first.addingTimeInterval(width * Double(index + 1)),
                                usd: sums[index] / Double(seen[index]))
        }
    }

    /// The mean of the points' volumes; nil when none report one.
    var averageVolume: Double? {
        let volumes = compactMap(\.volume).filter { $0.isFinite && $0 >= 0 }
        return volumes.isEmpty ? nil : volumes.reduce(0, +) / Double(volumes.count)
    }
}

extension Array where Element == VolumeBucket {
    func bucket(containing date: Date) -> VolumeBucket? {
        if let match = first(where: { $0.start <= date && date < $0.end }) { return match }
        // The last point sits exactly on the last slice's end.
        guard let last, date >= last.end else { return nil }
        return last
    }
}

// MARK: - Loading

/// One coin's chart as a screen shows it: the points, the range they belong
/// to, and whether loading failed. The coin screen and the expanded chart
/// share one, so the expanded chart opens with the line already drawn.
@MainActor
@Observable
final class PriceChartLoader {
    private(set) var points: [PricePoint] = []
    private(set) var loadedRange: PriceRange?
    private(set) var failed = false
    /// The range most recently asked for.
    private var requestedRange: PriceRange?

    /// The points, when they are this range's.
    func points(for range: PriceRange) -> [PricePoint] { loadedRange == range ? points : [] }

    /// Cached copy first (drawn at once), then the fresh one. Until either
    /// arrives, the previous range's points stay for the chart to dim.
    func load(_ token: TokenKind, _ range: PriceRange, from app: AppModel, animated: Bool = true) async {
        requestedRange = range
        if loadedRange != range {
            failed = false
            if let cached = app.cachedChart(for: token, range: range) {
                points = cached
                loadedRange = range
            }
        }
        do {
            let fresh = try await app.chart(for: token, range: range)
            // A retry isn't cancelled by a range change: drop its late answer.
            guard !Task.isCancelled, requestedRange == range else { return }
            withAnimation(animated ? .snappy : nil) {
                points = fresh
                loadedRange = range
                failed = false
            }
        } catch {
            guard !Task.isCancelled, requestedRange == range else { return }
            // A stale copy of this range is still worth showing; nothing isn't.
            if loadedRange != range { failed = true }
        }
    }
}

extension PriceChartView {
    /// The chart for a loader's state: this range's line, or the previous
    /// one dimmed while this range loads, or the failure state.
    init(loader: PriceChartLoader, range: PriceRange, showsVolume: Bool = false, showsExtremes: Bool = false,
         selection: Binding<Date?>, retry: @escaping () -> Void) {
        let current = loader.loadedRange == range
        self.init(points: loader.failed && !current ? [] : loader.points,
                  range: loader.loadedRange ?? range,
                  showsVolume: showsVolume, showsExtremes: showsExtremes,
                  dimmed: !current, failed: loader.failed,
                  selection: selection, retry: retry)
    }
}

// MARK: - Range pills

/// The range pills for a price chart. Six pills share a phone's width, so the
/// labels may shrink a little and stop growing at the first accessibility
/// size, instead of truncating to "…".
struct PriceRangePicker: View {
    @Binding var selection: PriceRange

    var body: some View {
        PillPicker(selection: $selection, options: PriceRange.allCases) { $0.title }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
