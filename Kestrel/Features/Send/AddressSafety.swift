import Foundation

/// What the wallet's own history says about a recipient.
enum RecipientHistory: Equatable {
    /// A real transfer went to this address before.
    case known
    /// No earlier transfer to it in the loaded history.
    case firstTime
    /// Not an address used before, but it starts or ends like one that was.
    case lookalike(of: String)
}

/// Defences against address poisoning: a scammer plants a transfer in your
/// history from an address made to look like one you use (same first and last
/// characters), hoping the next payment is copied from that row.
enum AddressSafety {
    /// Poisoning transfers carry nothing or next to nothing. The wallet itself
    /// never sends less than this (`AmountRules.minimumUnits`), and the fee
    /// makes a real payment this small unlikely.
    static let trustedMinimumUnits: UInt64 = 1_000_000

    /// Too small to treat its other side as an address you deal with: no
    /// "Repeat payment", no copying the address from it.
    static func isSuspicious(_ transfer: TokenTransfer) -> Bool {
        transfer.units < trustedMinimumUnits
    }

    /// Short forms hide the middle, so a match at either end is what fools the eye.
    private static let matchedEnd = 4
    /// "T" plus four: every address shares the first character.
    private static let matchedStart = 5

    static func looksAlike(_ a: String, _ b: String) -> Bool {
        a != b && (a.suffix(matchedEnd) == b.suffix(matchedEnd) || a.prefix(matchedStart) == b.prefix(matchedStart))
    }

    static func assess(recipient: String, ownAddress: String, transfers: [TokenTransfer]) -> RecipientHistory {
        let real = transfers.filter { !isSuspicious($0) }
        if real.contains(where: { $0.from == ownAddress && $0.to == recipient }) { return .known }
        // Anyone you paid or were really paid by is worth imitating.
        var seen = Set<String>()
        for transfer in real {
            let other = transfer.from == ownAddress ? transfer.to : transfer.from
            guard other != ownAddress, other != recipient, seen.insert(other).inserted else { continue }
            if looksAlike(recipient, other) { return .lookalike(of: other) }
        }
        return .firstTime
    }
}
