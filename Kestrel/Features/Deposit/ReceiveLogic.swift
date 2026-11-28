import Foundation

/// The pure parts of Receive: what the QR encodes, how the address is shown,
/// and what counts as a new incoming payment. Kept free of SwiftUI so it's testable.
enum ReceiveLogic {
    /// What the QR and the share sheet carry.
    ///
    /// No amount: the bare address. Every wallet and exchange understands it,
    /// so it's the safest default. With an amount: a `tron:` payment URI, the
    /// form TRON wallets read:
    ///
    ///     tron:<address>?amount=50.5&token=TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t  (USDT)
    ///     tron:<address>?amount=25&token=TRX                                    (TRX)
    ///
    /// `amount` is in whole coins with a `.` decimal point and no grouping.
    /// `token` is the TRC-20 contract for USDT. TRX, the native coin, is named
    /// explicitly too: a USDT-first scanner (Kestrel's own `PaymentRequest`
    /// included) would otherwise read a bare `amount=25` as 25 USDT.
    static func paymentPayload(address: String, token: TokenKind, units: UInt64?) -> String {
        guard let units, units > 0 else { return address }
        var uri = "tron:\(address)?amount=\(decimalAmount(units))"
        switch token {
        case .usdt: uri += "&token=\(USDT.contract)"
        case .trx: uri += "&token=TRX"
        }
        return uri
    }

    /// 50_500_000 → "50.5". Six decimals at most, trailing zeros dropped, no grouping.
    static func decimalAmount(_ units: UInt64) -> String {
        let whole = units / 1_000_000
        var fraction = String(format: "%06llu", units % 1_000_000)
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return fraction.isEmpty ? "\(whole)" : "\(whole).\(fraction)"
    }

    /// An amount the user typed, in base units (both coins have 6 decimals).
    /// Accepts a comma as the decimal separator.
    static func parseAmount(_ text: String) -> AmountInput {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return .empty }
        guard let units = USDT.units(from: cleaned) else {
            let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
            guard (1 ... 2).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
                  parts.contains(where: { !$0.isEmpty }) else { return .invalid }
            if parts.count == 2, parts[1].count > USDT.decimals { return .tooManyDecimals }
            return .tooLarge // well-formed digits that overflow
        }
        guard units > 0 else { return .zero }
        // Ten billion is far beyond any real request; it also keeps the URI sane.
        guard units <= maxRequestUnits else { return .tooLarge }
        return .valid(units)
    }

    static let maxRequestUnits: UInt64 = 10_000_000_000 * 1_000_000

    enum AmountInput: Equatable {
        case empty, invalid, zero, tooManyDecimals, tooLarge
        case valid(UInt64)
    }

    /// "TV2QjYfd8J…" → ["TV2Q", "jYfd", "8J…"]: groups of four are easy to compare by eye.
    static func addressGroups(_ address: String, size: Int = 4) -> [String] {
        guard size > 0 else { return [address] }
        var groups: [String] = []
        var current = ""
        for character in address {
            current.append(character)
            if current.count == size {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}

/// How a payment that just arrived compares with the amount being requested.
enum RequestOutcome: Equatable {
    case exact
    case over(by: UInt64)
    case short(by: UInt64)
    /// No request, or the payment is in the other coin: nothing to compare.
    case unrelated
}

extension ReceiveLogic {
    /// Compares only like with like: both coins have 6 decimals, so 25 TRX and
    /// 25 USDT are the same number of units and must never read as a match.
    static func outcome(paymentToken: TokenKind, paymentUnits: UInt64,
                        selectedToken: TokenKind, requestedUnits: UInt64?) -> RequestOutcome {
        guard paymentToken == selectedToken, let requested = requestedUnits, requested > 0 else { return .unrelated }
        if paymentUnits == requested { return .exact }
        return paymentUnits > requested ? .over(by: paymentUnits - requested) : .short(by: requested - paymentUnits)
    }

    /// Which of the payments from one poll gets the receipt: the one that
    /// answers the request (exact, else over, else short), else the first,
    /// which is the newest. nil when there are none.
    static func celebratedIndex(_ outcomes: [RequestOutcome]) -> Int? {
        guard !outcomes.isEmpty else { return nil }
        func rank(_ outcome: RequestOutcome) -> Int {
            switch outcome {
            case .exact: 0
            case .over: 1
            case .short: 2
            case .unrelated: 3
            }
        }
        return outcomes.indices.min { rank(outcomes[$0]) < rank(outcomes[$1]) }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// Watches the wallet for payments that arrive while Receive is open.
///
/// The first loaded snapshot is the baseline: anything already in the
/// history then is old. Before the history has loaded at all there's no
/// baseline, so the first load can't be mistaken for 25 new payments.
struct IncomingWatch: Equatable {
    private(set) var seenIDs: Set<String>?
    private(set) var trxBaseline: Int64?

    enum Event: Equatable {
        case usdt(TokenTransfer)
        case trx(sun: Int64)
    }

    /// Feed the latest wallet state; returns what's new since the last call.
    /// `loaded` is false until the history has been fetched at least once.
    /// USDT events come newest first.
    mutating func observe(history: [TokenTransfer], trxSun: Int64, myAddress: String,
                          loaded: Bool, watchTRX: Bool) -> [Event] {
        guard loaded else { return [] }
        let ids = Set(history.map(\.id))
        guard let seen = seenIDs else {
            seenIDs = ids
            trxBaseline = trxSun
            return []
        }
        let incoming = history
            .filter { !seen.contains($0.id) && $0.to == myAddress && $0.from != myAddress && $0.units > 0 }
            .sorted { $0.date > $1.date }
        // The history is a window of the latest 25, so keep old ids too.
        seenIDs = seen.union(ids)

        var events = incoming.map(Event.usdt)
        if let baseline = trxBaseline {
            if watchTRX, trxSun > baseline { events.append(.trx(sun: trxSun - baseline)) }
        }
        // A drop (fees paid elsewhere) resets the baseline, so a later top-up
        // is measured from the lower balance.
        trxBaseline = trxSun
        return events
    }
}
