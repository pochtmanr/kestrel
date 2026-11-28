import SwiftUI

/// What sending costs, whether this wallet can pay it, and how to top up.
/// Reached from Settings, Send, Receive and the TRX coin screen.
struct NetworkFeeInfoView: View {
    @Environment(AppModel.self) private var app
    @State private var copied = false

    /// The chain's fee prices: what's saved (or built in) at once, the node's
    /// own once it answers.
    @State private var parameters = TronClient.savedChainFeeParameters

    private var level: FuelLevel { app.fuelLevel }
    /// What a transfer burns for a wallet with nothing staked: to an address
    /// that holds USDT at the low end, to one that holds none at the high end.
    private var typicalFee: ClosedRange<Int64> { FeeEstimate.typicalRange(parameters: parameters) }
    /// The dearer case in dollars: nobody is surprised by paying less.
    private var feeUSD: Double? {
        app.prices[.trx].map { Double(typicalFee.upperBound) / 1_000_000 * $0.usd }
    }
    /// Transfers a 30 TRX top-up pays for, counted at the dearer case.
    private var topUpTransfers: Int { Int(Self.topUpSun / max(typicalFee.upperBound, 1)) }
    private static let topUpSun: Int64 = 30_000_000

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    price
                    fuel
                }
                how
                topUp
                if !app.activity.fees.isEmpty { paid }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle("Network fees")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            async let prices: Void = app.refreshPrices()
            // The demo wallet never touches the network.
            if !app.isDemo { parameters = await app.tron.chainFeeParameters() }
            await prices
        }
    }

    // MARK: The price

    /// The one number to remember, then the two rules beside each other.
    private var price: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("One USDT transfer costs")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "≈ \(FeeEstimate.rangeText(typicalFee))")
                        .font(Theme.Typography.amount(46))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(verbatim: "TRX")
                        .font(Theme.Typography.amount(24, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ember)
                }
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                if let feeUSD {
                    Text("up to about \(USDPrice.format(feeUSD)) at today's price")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                RuleTile(symbol: "arrow.up.right", color: Theme.Palette.ember, title: "Sending", value: "Paid in TRX")
                RuleTile(symbol: "arrow.down.left", color: Theme.Palette.positive, title: "Receiving", value: "Free")
            }
        }
        .padding(18)
        .padding(.top, 6)
        .surface(cornerRadius: Theme.Radius.hero)
    }

    // MARK: This wallet

    private var meterColor: Color {
        level == .good ? Theme.Palette.positive : level.color
    }

    private var fuel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your fee balance")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text(verbatim: "\(TRX.format(sun: app.trxSun)) TRX")
                        .font(Theme.Typography.amount(26))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                Spacer(minLength: 8)
                Label {
                    switch level {
                    case .good: Text("Ready")
                    case .low: Text("Running low")
                    case .empty: Text("Not enough")
                    }
                } icon: {
                    Image(systemName: level == .good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(meterColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(meterColor.opacity(0.14), in: .capsule)
            }

            FuelMeter(filled: Int(min(app.transfersLeft, Int64(FuelMeter.segments))), color: meterColor)

            Group {
                if level == .empty {
                    let missing = max(0, TRX.minimumForTransferSun - app.trxSun)
                    Text("Add at least \(TRX.format(sun: missing)) TRX to send USDT.")
                } else {
                    Text("Enough for about \(app.transfersLeft) transfers.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if level != .good {
                NavigationLink(value: HomeRoute.receiveToken(.trx)) {
                    Label("Add TRX", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .surface(cornerRadius: Theme.Radius.hero)
        .accessibilityElement(children: .contain)
    }

    // MARK: Why

    private var how: some View {
        SettingsGroup("How it works") {
            ExplainRow(symbol: "flame.fill", color: Theme.Palette.ember,
                       title: "TRON charges energy",
                       text: "Moving USDT uses network energy. A wallet with no staked energy pays for it by burning TRX.")
            SettingsDivider()
            ExplainRow(symbol: "person.badge.plus", color: Theme.Palette.warning,
                       title: "A first transfer costs more",
                       text: "Sending to an address that holds no USDT yet costs about twice as much: the network has to create its balance record.")
            SettingsDivider()
            ExplainRow(symbol: "wallet.bifold.fill", color: Theme.Palette.accent,
                       title: "Paid from your TRX",
                       text: "The fee comes out of your TRX balance, never out of the USDT you send. The recipient gets the full amount.")
            SettingsDivider()
            ExplainRow(symbol: "hand.raised.fill", color: Theme.Palette.positive,
                       title: "\(Brand.name) takes nothing",
                       text: "The whole fee goes to the TRON network. The app adds no charge of its own.")
        }
    }

    // MARK: Top up

    private var topUp: some View {
        VStack(spacing: 14) {
            SettingsGroup("How to add TRX") {
                StepRow(number: 1, text: "Buy TRX on any exchange, or use a wallet that already holds some.")
                SettingsDivider()
                StepRow(number: 2, text: "Withdraw it to your wallet address. Choose the TRON network.")
                SettingsDivider()
                StepRow(number: 3, text: "It arrives in about a minute. 30 TRX covers at least \(topUpTransfers) transfers.")
            }
            HStack(spacing: 12) {
                NavigationLink(value: HomeRoute.receiveToken(.trx)) {
                    Label("Receive TRX", systemImage: "arrow.down.left")
                }
                .buttonStyle(PrimaryButtonStyle())
                if app.address != nil {
                    Button(action: copyAddress) {
                        Label {
                            if copied { Text("Address copied") } else { Text("Copy my address") }
                        } icon: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var paid: some View {
        let fees = app.activity.fees.values
        return SettingsGroup("So far") {
            HStack {
                Text("Fees paid").foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(TRX.format(sun: fees.reduce(0, +))) TRX").monospacedDigit()
                    Text("on \(fees.count) transfers")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .accessibilityElement(children: .combine)
        }
    }

    private func copyAddress() {
        guard let address = app.address else { return }
        Clipboard.copy(address)
        withAnimation(.snappy) { copied = true }
        AccessibilityNotification.Announcement(tr("Address copied")).post()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { copied = false }
        }
    }
}

/// "Sending: paid in TRX" / "Receiving: free", as a small tinted tile.
private struct RuleTile: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let value: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.16), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Palette.textPrimary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.Palette.surfaceRaised, in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Transfers the balance pays for, as a row of cells (the last one means "or more").
private struct FuelMeter: View {
    static let segments = 5
    let filled: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<Self.segments, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? color : Theme.Palette.surfaceRaised)
                    .frame(height: 8)
            }
        }
        .animation(.snappy, value: filled)
        .accessibilityHidden(true)
    }
}

private struct ExplainRow: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.Palette.textPrimary)
                Text(text).font(.subheadline).foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.Palette.accentText)
                .frame(width: 32, height: 32)
                .background(Theme.Palette.accent.opacity(0.16), in: .circle)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
