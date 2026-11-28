import SwiftUI

/// The coin's chart on a whole screen (portrait): a tall plot with volume and
/// the high and low marked, the range's numbers under it, and the range pills
/// at the bottom where thumbs are. Presented as a cover from the coin screen,
/// sharing its range and its loaded chart.
struct ExpandedChartView: View {
    let token: TokenKind
    @Binding var range: PriceRange
    let loader: PriceChartLoader

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Date?

    private var price: TokenPrice? { app.prices[token] }
    private var points: [PricePoint] { loader.points(for: range) }
    private var selectedPoint: PricePoint? { selection.flatMap { points.nearest(to: $0) } }

    /// The change over the shown range; 24h straight from the quote for 1D.
    private var rangeChange: Double? {
        if range == .day, let change = price?.change24h { return change }
        return points.changePercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            titleBar
            priceLabel
            PriceChartView(loader: loader, range: range, showsVolume: true, showsExtremes: true, selection: $selection) {
                Task { await load() }
            }
            .frame(minHeight: 160, maxHeight: .infinity)
            stats
            PriceRangePicker(selection: $range)
                .onChange(of: range) { selection = nil }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .readableWidth(Theme.Layout.wideContent)
        .background(Theme.Palette.background.ignoresSafeArea())
        // A chart screen: past this size the plot would have no room left.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .task(id: range) { await load() }
    }

    private func load() async {
        await loader.load(token, range, from: app, animated: !reduceMotion)
    }

    // MARK: Header

    private var titleBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            TokenIcon(token: token, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: token.name)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(verbatim: token.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.s)
            GlassGlyph(symbol: "xmark", label: "Close") { dismiss() }
        }
    }

    @ViewBuilder
    private var priceLabel: some View {
        let shown = selectedPoint?.usd ?? price?.usd
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: shown.map(USDPrice.price) ?? "—")
                .font(Theme.Typography.amount(40, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Stats

    /// The range in four numbers. Always four cells, a dash where there's
    /// nothing yet, so the chart above keeps its height while a range loads.
    private var stats: some View {
        let low = points.map(\.usd).min()
        let high = points.map(\.usd).max()
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .topLeading),
                            count: typeSize.isAccessibilitySize ? 2 : 4)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.m) {
            StatCell(title: "Highest", value: high.map(USDPrice.price))
            StatCell(title: "Lowest", value: low.map(USDPrice.price))
            StatCell(title: "Change", value: rangeChange.map(USDPrice.percent),
                     tint: rangeChange.map { $0 >= 0 ? Theme.Palette.positive : Theme.Palette.danger })
            StatCell(title: range.averageVolumeCaption, value: points.averageVolume.map(USDPrice.compact))
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: Theme.Radius.tile)
    }
}

private struct StatCell: View {
    let title: LocalizedStringKey
    let value: String?
    var tint: Color?

    var body: some View {
        // The number first: the values line up across the cells even when a
        // longer title (or a translation) wraps to a second line.
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value ?? "—")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint ?? Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Expanded chart") {
    let app = AppModel()
    app.loadDemo()
    return ExpandedChartView(token: .trx, range: .constant(.week), loader: PriceChartLoader())
        .environment(app)
}
#endif
