import SwiftUI
import WidgetKit

@main
struct KestrelWidgets: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
    }
}

struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedWallet.widgetKind, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
                // The language chosen in the app's Settings, not only the phone's.
                .transformEnvironment(\.locale) { if let locale = AppLanguage.current.locale { $0 = locale } }
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Balance")
        // Resolved to a plain string first: WidgetKit asserts on a localised key that carries an argument.
        .description(Text(verbatim: tr("Your \(Brand.name) USDT balance at a glance.")))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - Timeline

struct BalanceEntry: TimelineEntry {
    enum State { case noWallet, ready(SharedWallet.Snapshot) }

    let date: Date
    let state: State
    let hidden: Bool

    static let preview = BalanceEntry(
        date: .now,
        state: .ready(.init(address: "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH", usdtUnits: 1_284_500_000, trxSun: 42_000_000, updatedAt: .now,
                            recent: [
                                TokenTransfer(id: "p1", date: .now.addingTimeInterval(-1_800), from: "TMuA6YqfCeX8EhbfYEg5y7S4DqzSJireY9",
                                              to: "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH", units: 500_000_000),
                                TokenTransfer(id: "p2", date: .now.addingTimeInterval(-26_000), from: "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH",
                                              to: "TDAeAFiB38L4mCAE8AhGRN7QUbG7DUv8tV", units: 120_000_000),
                            ])),
        hidden: false
    )
}

struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(context.isPreview && SharedWallet.snapshot == nil ? .preview : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        // WidgetKit calls completion exactly once; it's safe to hand to the task.
        nonisolated(unsafe) let completion = completion
        Task {
            // Refresh from the TRON network; fall back to the app's last value offline.
            if var snapshot = SharedWallet.snapshot {
                let client = TronClient()
                if let usdt = try? await client.usdtBalance(of: snapshot.address),
                   let trx = try? await client.trxBalance(of: snapshot.address) {
                    snapshot.usdtUnits = usdt
                    snapshot.trxSun = trx
                    snapshot.updatedAt = .now
                    if let recent = try? await client.usdtHistory(of: snapshot.address, limit: SharedWallet.recentCount) {
                        snapshot.recent = recent
                    }
                    SharedWallet.save(snapshot)
                }
            }
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [currentEntry()], policy: .after(next)))
        }
    }

    private func currentEntry() -> BalanceEntry {
        guard let snapshot = SharedWallet.snapshot else {
            return BalanceEntry(date: .now, state: .noWallet, hidden: false)
        }
        return BalanceEntry(date: .now, state: .ready(snapshot), hidden: SharedWallet.isBalanceHidden)
    }
}

// MARK: - Views

private let brand = Theme.Palette.accent

private struct WidgetBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.background
            LinearGradient(colors: [brand.opacity(0.45), brand.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BalanceEntry

    var body: some View {
        switch entry.state {
        case .noWallet:
            noWallet
        case .ready(let snapshot):
            switch family {
            case .systemMedium: medium(snapshot)
            case .systemLarge: large(snapshot)
            case .accessoryRectangular: rectangular(snapshot)
            case .accessoryInline: Text("\(Brand.name) \(amount(snapshot.usdtUnits)) USDT").privacySensitive()
            case .accessoryCircular: circular(snapshot)
            default: small(snapshot)
            }
        }
    }

    // MARK: Families

    private func small(_ snapshot: SharedWallet.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            brandRow
            Spacer(minLength: 6)
            Text("USDT balance").font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            balance(snapshot.usdtUnits, size: 30)
            Spacer(minLength: 6)
            footer(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ snapshot: SharedWallet.Snapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                brandRow
                Spacer(minLength: 6)
                Text("Total balance").font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                balance(snapshot.usdtUnits, size: 32)
                Spacer(minLength: 6)
                footer(snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                tokenRow(symbol: "₮", color: Theme.Palette.usdt, name: "USDT",
                         value: amount(snapshot.usdtUnits))
                tokenRow(symbol: "▼", color: Theme.Palette.trx, name: "TRX",
                         value: entry.hidden ? "••••" : TRX.format(sun: snapshot.trxSun),
                         warning: snapshot.trxSun < TRX.minimumForTransferSun)
            }
            .frame(width: 138)
        }
    }

    /// The iPad home screen's size: the medium layout plus the latest transfers.
    private func large(_ snapshot: SharedWallet.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            medium(snapshot).frame(height: 120)
            Divider().overlay(.white.opacity(0.15))
            Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            let recent = snapshot.recent ?? []
            if recent.isEmpty {
                Text("No transfers yet").font(.caption).foregroundStyle(.white.opacity(0.6))
            } else {
                VStack(spacing: 10) {
                    ForEach(recent) { transfer in
                        recentRow(transfer, me: snapshot.address)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func recentRow(_ transfer: TokenTransfer, me: String) -> some View {
        let outgoing = transfer.from == me
        return HStack(spacing: 10) {
            Image(systemName: outgoing ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(outgoing ? .white.opacity(0.8) : Theme.Palette.positive)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.08), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(outgoing ? "Sent" : "Received").font(.caption.weight(.semibold)).foregroundStyle(.white)
                Text(transfer.date, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(entry.hidden ? "••••" : "\(outgoing ? "−" : "+")\(USDT.format(units: transfer.units))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(outgoing ? .white : Theme.Palette.positive)
                .privacySensitive()
        }
    }

    private func rectangular(_ snapshot: SharedWallet.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("\(Brand.name)", systemImage: "wallet.bifold.fill").font(.caption2.weight(.semibold))
            Text("\(entry.hidden ? "$••••" : "$" + amount(snapshot.usdtUnits))")
                .font(.headline.monospacedDigit())
                .minimumScaleFactor(0.6)
            Text("USDT · TRON").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
    }

    private func circular(_ snapshot: SharedWallet.Snapshot) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("₮").font(.caption.bold())
                Text(entry.hidden ? "••" : compact(snapshot.usdtUnits))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.5)
            }
        }
        .privacySensitive()
    }

    private var noWallet: some View {
        VStack(alignment: .leading, spacing: 6) {
            if family == .accessoryInline {
                Text("\(Brand.name)")
            } else {
                brandRow
                Spacer(minLength: 0)
                Text("Open \(Brand.name) to set up your wallet").font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private var brandRow: some View {
        HStack(spacing: 6) {
            Image("Logo").resizable().frame(width: 20, height: 20).clipShape(.rect(cornerRadius: Theme.Radius.xxs))
            Text("\(Brand.name)").font(.caption.weight(.semibold)).foregroundStyle(.white)
        }
    }

    private func balance(_ units: UInt64, size: CGFloat) -> some View {
        Text(entry.hidden ? "$••••" : "$\(amount(units))")
            .font(.system(size: size, weight: .bold, design: Theme.Typography.numeric).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .contentTransition(.numericText())
            .privacySensitive()
    }

    private func footer(_ snapshot: SharedWallet.Snapshot) -> some View {
        Text(snapshot.updatedAt, style: .relative)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
    }

    private func tokenRow(symbol: String, color: Color, name: String, value: String, warning: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color, in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text(name).font(.caption.weight(.semibold))
                    if warning { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
                }
                Text(value).font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: Theme.Radius.s))
        .privacySensitive()
    }

    private func amount(_ units: UInt64) -> String {
        entry.hidden ? "••••" : USDT.format(units: units)
    }

    /// 1_284_500_000 → "1.3K"
    private func compact(_ units: UInt64) -> String {
        let value = Double(units) / 1_000_000
        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0 ... 1)))
    }
}

#Preview(as: .systemSmall) {
    BalanceWidget()
} timeline: {
    BalanceEntry.preview
}

#Preview(as: .systemLarge) {
    BalanceWidget()
} timeline: {
    BalanceEntry.preview
}

#Preview(as: .systemMedium) {
    BalanceWidget()
} timeline: {
    BalanceEntry.preview
}
