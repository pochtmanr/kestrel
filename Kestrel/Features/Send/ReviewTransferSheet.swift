import SwiftUI

/// The last look before PIN or Face ID: who, how much, what it costs, and
/// that it can't be undone.
struct ReviewTransferSheet: View {
    let recipient: String
    let units: UInt64
    /// The Send flow's fee estimate, re-run here with the amount being sent.
    let fees: FeeEstimator
    /// Face ID is up: the confirm button waits.
    let authorizing: Bool
    let onConfirm: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var amountText: String { SendFormat.usdt(units) }
    private var estimate: FeeEstimate? { fees.estimate(for: recipient) }
    /// The most the fee can take: what the wallet was checked against.
    private var requiredSun: Int64 { estimate?.requiredSun ?? TRX.minimumForTransferSun }
    /// The likely fee, for the fiat lines: the ceiling when there's no estimate.
    private var burnSun: Int64 { estimate?.burnSun ?? TRX.minimumForTransferSun }

    private var amountUSD: Double? {
        app.prices[.usdt].map { Double(units) / 1_000_000 * $0.usd }
    }

    private var feeUSD: Double? {
        app.prices[.trx].map { Double(burnSun) / 1_000_000 * $0.usd }
    }

    /// What the wallet's history says about this address (see `AddressSafety`).
    private var recipientHistory: RecipientHistory {
        let transfers = app.activity.transfers.isEmpty ? app.history : app.activity.transfers
        return AddressSafety.assess(recipient: recipient, ownAddress: app.address ?? "", transfers: transfers)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("You're sending").foregroundStyle(.secondary)
                        Text(verbatim: "\(amountText) USDT")
                            .font(Theme.Typography.amount(40, weight: .bold).monospacedDigit())
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if let amountUSD {
                            Text(verbatim: "≈ \(USDPrice.format(amountUSD))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        recipientRow
                        Divider().padding(.leading, 16)
                        row("Network") { Text("TRON (TRC-20)") }
                        Divider().padding(.leading, 16)
                        row("Network fee") {
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 6) {
                                    if fees.isLoading { ProgressView().controlSize(.small) }
                                    // No estimate at all reads as the ceiling, never as a range.
                                    NetworkFeeText(estimate: estimate ?? .fallback)
                                }
                                Text(feeUSD.map { tr("≈ \(USDPrice.format($0)), paid in TRX") }
                                    ?? tr("Paid in TRX"))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if estimate?.isFirstTransferToRecipient == true {
                                    Text("First transfer to this address costs more.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Divider().padding(.leading, 16)
                        row("Total") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: "\(amountText) USDT").font(.body.weight(.semibold).monospacedDigit())
                                Text("+ up to \(FeeEstimate.trxText(sun: requiredSun)) TRX fee")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if let amountUSD, let feeUSD {
                                    Text(verbatim: "≈ \(USDPrice.format(amountUSD + feeUSD))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .surface(cornerRadius: Theme.Radius.card)

                    recipientCaution

                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Transfers can't be undone").font(.subheadline.weight(.semibold))
                            Text("Once it's sent, nobody can cancel or reverse it, Kastrel included. Make sure the address is right.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Palette.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.Palette.warning.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, 16)
                .readableWidth()
            }
            .background(Theme.Palette.background)
            .safeAreaInset(edge: .bottom) {
                Button(action: onConfirm) {
                    if authorizing {
                        ProgressView().tint(.white)
                    } else {
                        Label("Confirm with \(Biometrics.isEnabled ? Biometrics.label : tr("PIN"))",
                              systemImage: Biometrics.isEnabled ? Biometrics.symbol : "lock.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(authorizing)
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, 8)
                .readableWidth()
                .background(Theme.Palette.background)
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() }.disabled(authorizing) }
            }
        }
        .presentationDetents([.large])
        .task {
            // The demo wallet never touches the network; its estimate is already set.
            guard !app.isDemo, let from = app.address else { return }
            fees.update(from: from, to: recipient, units: units, balance: app.usdtUnits, immediately: true)
        }
        .interactiveDismissDisabled(authorizing)
    }

    /// A lookalike of an address used before is the mark of address poisoning:
    /// said loudly. A new address is only worth a second look.
    @ViewBuilder
    private var recipientCaution: some View {
        switch recipientHistory {
        case .known:
            EmptyView()
        case .firstTime:
            caution(
                title: "New address",
                text: tr("There's no earlier transfer to this address in your history. Check every character."),
                tint: Theme.Palette.warning
            )
        case .lookalike(let other):
            caution(
                title: "This address looks like another one",
                text: tr("It isn't \(other.shortAddress), an address from your history, but it starts or ends the same way. Scammers make such lookalikes. Compare the full address with the one you were given."),
                tint: Theme.Palette.danger
            )
        }
    }

    private func caution(title: LocalizedStringKey, text: String, tint: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Short address to scan at a glance, the full one to check character by character.
    private var recipientRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("To").foregroundStyle(.secondary)
                Spacer()
                Text(recipient.shortAddress).font(.body.weight(.semibold).monospaced())
            }
            Text(recipient)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("To \(recipient)")
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            value().multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
    }
}

enum SendFormat {
    /// Two decimals, or up to six when the amount has more.
    static func usdt(_ units: UInt64) -> String {
        USDT.format(units: units, fractionDigits: units % 10_000 == 0 ? 2 : 6)
    }
}
