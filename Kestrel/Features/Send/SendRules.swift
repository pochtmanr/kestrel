import Foundation

// Pure rules behind the Send screens: what a pasted or scanned text means,
// whether an address or amount can be sent, and what a failed send tells the
// user. No UI and no network here, so `SendTests` can pin every case down.

// MARK: - Payment requests

/// An address, maybe with an amount, from a paste, a QR code or a prefill.
/// Accepts a bare address, `tron:T…?amount=5`, `tron://T…`, `usdt:T…` and a
/// Tronscan address link.
struct PaymentRequest: Equatable {
    var address: String
    /// The amount exactly as the request wrote it; validated like typed input.
    var amount: String?
    /// The request names another coin (e.g. TRX): its amount isn't USDT, so it's dropped.
    var otherToken = false

    private static let schemes: Set<String> = ["tron", "usdt", "trc20", "tether"]
    private static let tokenKeys: Set<String> = ["token", "contract", "contract_address", "asset", "coin", "currency"]

    static func parse(_ raw: String) -> PaymentRequest? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            // tronscan.org/#/address/T…: take the address, nothing else.
            guard lower.contains("tronscan"), let range = text.range(of: "/address/") else { return nil }
            let tail = text[range.upperBound...]
            let address = String(tail.prefix { $0.isLetter || $0.isNumber })
            return address.isEmpty ? nil : PaymentRequest(address: address)
        }

        if let colon = text.firstIndex(of: ":") {
            guard schemes.contains(text[..<colon].lowercased()) else { return nil }
            text = String(text[text.index(after: colon)...])
            while text.hasPrefix("/") { text.removeFirst() }
        }

        var address = text
        var query = ""
        if let mark = text.firstIndex(of: "?") {
            address = String(text[..<mark])
            query = String(text[text.index(after: mark)...])
        }
        address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }

        var request = PaymentRequest(address: address)
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "amount" {
                request.amount = value.isEmpty ? nil : value
            } else if tokenKeys.contains(key), !value.isEmpty {
                let isUSDT = value.uppercased() == "USDT" || value.uppercased() == "TRC20-USDT" || value == USDT.contract
                if !isUSDT { request.otherToken = true }
            }
        }
        if request.otherToken { request.amount = nil }
        return request
    }

    /// Worth rewriting the field for: anything beyond a bare address.
    static func isRequestLike(_ text: String) -> Bool {
        text.contains(":") || text.contains("?")
    }
}

// MARK: - Recipient

enum RecipientCheck: Equatable {
    case empty
    /// Still being typed: plausible so far, too short to judge.
    case incomplete(characters: Int)
    case valid
    case problem(RecipientProblem)

    var isValid: Bool { self == .valid }
}

enum RecipientProblem: Equatable {
    case ethereumAddress
    case invalidCharacters
    case notTRON
    case checksum
    case ownAddress
    case tokenContract

    var message: String {
        switch self {
        case .ethereumAddress:
            tr("That looks like an Ethereum address. Kastrel sends USDT on TRON only: TRON addresses start with T.")
        case .invalidCharacters:
            tr("That isn't a TRON address. It has characters an address can't contain.")
        case .notTRON:
            tr("That isn't a TRON address. TRON addresses start with T and are 34 characters long.")
        case .checksum:
            tr("That isn't a valid TRON address. Check it for a typo.")
        case .ownAddress:
            tr("That's your own address. Enter the address you're sending to.")
        case .tokenContract:
            tr("That's the USDT token contract, not a wallet. USDT sent there is lost.")
        }
    }
}

enum RecipientRules {
    static let addressLength = 34
    private static let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func check(_ raw: String, ownAddress: String?) -> RecipientCheck {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        let lower = text.lowercased()
        if lower.hasPrefix("0x") || lower.hasPrefix("ethereum:") { return .problem(.ethereumAddress) }
        if TronAddress.isValid(text) {
            if text == ownAddress { return .problem(.ownAddress) }
            if text == USDT.contract { return .problem(.tokenContract) }
            return .valid
        }
        guard text.allSatisfy(base58.contains) else { return .problem(.invalidCharacters) }
        guard text.hasPrefix("T"), text.count <= addressLength else { return .problem(.notTRON) }
        return text.count < addressLength ? .incomplete(characters: text.count) : .problem(.checksum)
    }
}

// MARK: - Amount

enum AmountCheck: Equatable {
    case empty
    case valid(UInt64)
    case problem(AmountProblem)

    var units: UInt64? {
        if case .valid(let units) = self { return units }
        return nil
    }
}

enum AmountProblem: Equatable {
    case malformed
    case tooManyDecimals
    case zero
    case belowMinimum
    case exceedsBalance(UInt64)
    /// The TRX balance can't pay the network fee.
    case needsTRX
    /// Balances haven't loaded yet, so the amount can't be checked.
    case balanceUnknown

    var message: String {
        switch self {
        case .malformed: tr("That isn't a valid amount.")
        case .tooManyDecimals: tr("USDT has at most 6 decimal places.")
        case .zero: tr("Enter an amount above zero.")
        case .belowMinimum: tr("The minimum transfer is 1 USDT.")
        case .exceedsBalance(let balance):
            tr("That's more than your balance of \(USDT.format(units: balance, fractionDigits: balance % 10_000 == 0 ? 2 : 6)) USDT.")
        case .needsTRX: tr("Not enough TRX for the network fee.")
        case .balanceUnknown: tr("Checking your balance…")
        }
    }

    /// A caution the user fixes elsewhere, not a typing mistake.
    var isWarning: Bool { self == .needsTRX || self == .balanceUnknown }
}

enum AmountRules {
    /// Kept from the first release: below this the fee outweighs the transfer.
    static let minimumUnits: UInt64 = 1_000_000

    /// `usdtUnits` / `trxSun` are nil until the balances have loaded. `feeSun`
    /// is what the wallet must hold for the fee: the live estimate's required
    /// figure once there is one, the conservative constant until then.
    static func check(_ raw: String, usdtUnits: UInt64?, trxSun: Int64?,
                      feeSun: Int64 = TRX.minimumForTransferSun) -> AmountCheck {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .empty }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigitLike) }),
              parts.contains(where: { !$0.isEmpty })
        else { return .problem(.malformed) }
        if parts.count == 2, parts[1].count > USDT.decimals { return .problem(.tooManyDecimals) }
        guard let units = USDT.units(from: text) else { return .problem(.malformed) }
        if units == 0 { return .problem(.zero) }
        if units < minimumUnits { return .problem(.belowMinimum) }
        guard let usdtUnits, let trxSun else { return .problem(.balanceUnknown) }
        if units > usdtUnits { return .problem(.exceedsBalance(usdtUnits)) }
        if trxSun < feeSun { return .problem(.needsTRX) }
        return .valid(units)
    }

    /// Base units as keypad text: "2481.35", no grouping, no trailing zeros.
    static func text(units: UInt64) -> String {
        let whole = units / 1_000_000
        var fraction = String(format: "%06llu", units % 1_000_000)
        while fraction.last == "0" { fraction.removeLast() }
        return fraction.isEmpty ? "\(whole)" : "\(whole).\(fraction)"
    }
}

private extension Character {
    var isASCIIDigitLike: Bool { ("0" ... "9").contains(self) }
}

// MARK: - Failures

/// What a failed send means for the user, mapped from what `sendUSDT` threw.
///
/// `sendUSDT` builds and broadcasts in one call, so an error doesn't say which
/// step failed. Anything that could have come after the broadcast reached the
/// network is `outcomeUnknown`: the transfer may have gone through, and
/// sending again could pay twice.
enum SendFailure: Equatable {
    /// The request never left the phone (no connection, host unreachable).
    case offline
    /// HTTP 429: TronGrid refused the request before handling it.
    case rateLimited
    case insufficientTRX
    case insufficientUSDT
    /// The network refused the transfer, with its message.
    case rejected(String)
    /// A timeout, a dropped connection or an unreadable reply: maybe sent.
    case outcomeUnknown
    /// The keys aren't in this device's Keychain.
    case walletMissing
    /// Anything else. Treated like `outcomeUnknown`: no retry.
    case unknown(String)

    /// Safe to send the same transfer again: it certainly didn't go through.
    var allowsRetry: Bool {
        switch self {
        case .offline, .rateLimited, .rejected: true
        default: false
        }
    }

    /// The user must check Activity before trying again.
    var mightHaveSent: Bool {
        switch self {
        case .outcomeUnknown, .unknown: true
        default: false
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed,
        .appTransportSecurityRequiresSecureConnection,
    ]

    static func from(_ error: Error, units: UInt64, usdtBalance: UInt64) -> SendFailure {
        if error is WalletMissing { return .walletMissing }
        if let url = error as? URLError {
            return offlineCodes.contains(url.code) ? .offline : .outcomeUnknown
        }
        guard let failure = error as? TronClient.Failure else {
            return .unknown((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        switch failure {
        case .rateLimited:
            return .rateLimited
        case .http(let code):
            // A 4xx is refused before processing; a 5xx may have been mid-broadcast.
            return (400 ..< 500).contains(code)
                ? .rejected(tr("The network refused the request (HTTP \(code))."))
                : .outcomeUnknown
        case .badResponse:
            return .outcomeUnknown
        case .rejected(let message):
            return fromNetworkMessage(message, units: units, usdtBalance: usdtBalance)
        }
    }

    /// TronGrid's refusal text, sorted into what the user can do about it.
    static func fromNetworkMessage(_ message: String, units: UInt64, usdtBalance: UInt64) -> SendFailure {
        let text = message.lowercased()
        // The same transfer is already on the network.
        if text.contains("dup") { return .outcomeUnknown }
        if text.contains("exceeds balance") || text.contains("usdt") { return .insufficientUSDT }
        let feeWords = ["energy", "bandwidth", "bandwith", "resource", "trx", "fee"]
        let balanceWords = ["balance", "insufficient", "not enough", "does not exist"]
        if feeWords.contains(where: text.contains) && (balanceWords.contains(where: text.contains) || text.contains("energy")) {
            return .insufficientTRX
        }
        if balanceWords.contains(where: text.contains) {
            // "balance is not sufficient" is TRON's own (TRX) balance, unless USDT is what's short.
            return units > usdtBalance ? .insufficientUSDT : .insufficientTRX
        }
        return .rejected(message)
    }

    var title: String {
        switch self {
        case .offline: tr("No connection")
        case .rateLimited: tr("The network is busy")
        case .insufficientTRX: tr("Not enough TRX for the fee")
        case .insufficientUSDT: tr("Not enough USDT")
        case .rejected: tr("The network declined this transfer")
        case .outcomeUnknown: tr("We couldn't confirm this transfer")
        case .walletMissing: tr("Wallet not found")
        case .unknown: tr("Something went wrong")
        }
    }

    var message: String {
        switch self {
        case .offline:
            tr("Kastrel couldn't reach the TRON network. Nothing was sent. Check your connection and try again.")
        case .rateLimited:
            tr("The TRON network turned the request away because of heavy traffic. Nothing was sent. Try again in a few seconds.")
        case .insufficientTRX:
            tr("Every USDT transfer burns about 7–14 TRX of network energy, paid from this wallet. Nothing was sent. Add TRX, then try again.")
        case .insufficientUSDT:
            tr("Your USDT balance is lower than this amount. Nothing was sent. Choose a smaller amount.")
        case .rejected:
            tr("Nothing was sent. You can try again, or change the transfer.")
        case .outcomeUnknown:
            tr("The network stopped answering after the transfer was sent to it. It may still go through. Check Activity before you send again, so you don't pay twice.")
        case .walletMissing:
            tr("This device doesn't have the wallet's keys. Restore the wallet from its recovery phrase to send.")
        case .unknown:
            tr("We can't tell whether the transfer went through. Check Activity before you send again, so you don't pay twice.")
        }
    }

    /// The network's or the system's own words, when they add something.
    var detail: String? {
        switch self {
        case .rejected(let message), .unknown(let message): message.isEmpty ? nil : message
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .rateLimited: "hourglass"
        case .insufficientTRX: "bolt.slash"
        case .insufficientUSDT: "wallet.bifold"
        case .rejected: "xmark.octagon"
        case .outcomeUnknown, .unknown: "questionmark.circle"
        case .walletMissing: "key.slash"
        }
    }
}

/// Thrown when the Keychain has no wallet to sign with.
struct WalletMissing: Error {}

// MARK: - Finding a transfer whose outcome is unknown

enum SendOutcome {
    /// A confirmed transfer that matches one we tried to send, so an unclear
    /// failure can turn into a success without sending again.
    static func match(in history: [TokenTransfer], from: String, to: String, units: UInt64,
                      since start: Date, excluding known: Set<String>) -> TokenTransfer? {
        // A minute of slack: the block time can trail the phone's clock.
        let earliest = start.addingTimeInterval(-60)
        return history.first {
            $0.from == from && $0.to == to && $0.units == units && $0.date >= earliest && !known.contains($0.id)
        }
    }
}
