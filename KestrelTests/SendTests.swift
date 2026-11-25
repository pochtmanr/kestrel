import Foundation
import XCTest
@testable import Kestrel

final class SendTests: XCTestCase {
    private let valid = "TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvd"
    private let mine = "TV2QjYfd8Js2JhDfqKzZMLBscYtBkxU9ek"

    // MARK: Payment requests

    func testParsesBareAddress() {
        XCTAssertEqual(PaymentRequest.parse("  \(valid)\n"), PaymentRequest(address: valid))
    }

    func testParsesTronURIWithAmount() {
        XCTAssertEqual(PaymentRequest.parse("tron:\(valid)?amount=12.5"), PaymentRequest(address: valid, amount: "12.5"))
        XCTAssertEqual(PaymentRequest.parse("TRON://\(valid)?amount=3"), PaymentRequest(address: valid, amount: "3"))
        XCTAssertEqual(PaymentRequest.parse("usdt:\(valid)?label=Rent&amount=100"), PaymentRequest(address: valid, amount: "100"))
        XCTAssertEqual(PaymentRequest.parse("\(valid)?amount=7"), PaymentRequest(address: valid, amount: "7"))
    }

    func testKeepsAmountForUSDTTokenAndDropsItForOtherCoins() {
        XCTAssertEqual(PaymentRequest.parse("tron:\(valid)?amount=5&token=USDT")?.amount, "5")
        XCTAssertEqual(PaymentRequest.parse("tron:\(valid)?amount=5&contract=\(USDT.contract)")?.amount, "5")
        let trx = PaymentRequest.parse("tron:\(valid)?amount=5&token=TRX")
        XCTAssertNil(trx?.amount)
        XCTAssertEqual(trx?.otherToken, true)
        XCTAssertEqual(trx?.address, valid)
    }

    func testParsesTronscanLink() {
        XCTAssertEqual(PaymentRequest.parse("https://tronscan.org/#/address/\(valid)/transfers")?.address, valid)
        XCTAssertNil(PaymentRequest.parse("https://example.com/address/\(valid)"))
    }

    func testRejectsForeignSchemesAndEmptyText() {
        XCTAssertNil(PaymentRequest.parse("ethereum:0xabc?value=1"))
        XCTAssertNil(PaymentRequest.parse("bitcoin:bc1qxyz"))
        XCTAssertNil(PaymentRequest.parse("   "))
        XCTAssertNil(PaymentRequest.parse("tron:?amount=1"))
    }

    // MARK: Recipient

    func testRecipientChecks() {
        XCTAssertEqual(RecipientRules.check("", ownAddress: mine), .empty)
        XCTAssertEqual(RecipientRules.check(valid, ownAddress: mine), .valid)
        XCTAssertEqual(RecipientRules.check(" \(valid) ", ownAddress: mine), .valid)
        XCTAssertEqual(RecipientRules.check("TXJg", ownAddress: mine), .incomplete(characters: 4))
        XCTAssertEqual(RecipientRules.check(mine, ownAddress: mine), .problem(.ownAddress))
        XCTAssertEqual(RecipientRules.check(USDT.contract, ownAddress: mine), .problem(.tokenContract))
        XCTAssertEqual(RecipientRules.check("0x52908400098527886E0F7030069857D2E4169EE7", ownAddress: mine), .problem(.ethereumAddress))
        XCTAssertEqual(RecipientRules.check("TXJg…ccvd", ownAddress: mine), .problem(.invalidCharacters))
        XCTAssertEqual(RecipientRules.check("TXJgMdjVX5dKiQaUi9Qob0", ownAddress: mine), .problem(.invalidCharacters), "0 isn't Base58")
        XCTAssertEqual(RecipientRules.check("AXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvd", ownAddress: mine), .problem(.notTRON))
        XCTAssertEqual(RecipientRules.check(valid + "a", ownAddress: mine), .problem(.notTRON))
        XCTAssertEqual(RecipientRules.check("TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvx", ownAddress: mine), .problem(.checksum))
    }

    // MARK: Amount

    private func check(_ text: String, usdt: UInt64? = 100_000_000, trx: Int64? = 50_000_000) -> AmountCheck {
        AmountRules.check(text, usdtUnits: usdt, trxSun: trx)
    }

    func testAmountChecks() {
        XCTAssertEqual(check(""), .empty)
        XCTAssertEqual(check("12.5"), .valid(12_500_000))
        XCTAssertEqual(check("100"), .valid(100_000_000), "the whole balance is fine")
        XCTAssertEqual(check("0"), .problem(.zero))
        XCTAssertEqual(check("0.000"), .problem(.zero))
        XCTAssertEqual(check("0.5"), .problem(.belowMinimum))
        XCTAssertEqual(check("1.1234567"), .problem(.tooManyDecimals))
        XCTAssertEqual(check("1.2.3"), .problem(.malformed))
        XCTAssertEqual(check("abc"), .problem(.malformed))
        XCTAssertEqual(check("."), .problem(.malformed))
        XCTAssertEqual(check("-5"), .problem(.malformed))
        XCTAssertEqual(check("100.000001"), .problem(.exceedsBalance(100_000_000)))
        XCTAssertEqual(check("5", trx: 13_999_999), .problem(.needsTRX))
        XCTAssertEqual(check("5", usdt: nil, trx: nil), .problem(.balanceUnknown))
        XCTAssertEqual(check("99999999999999999999"), .problem(.malformed), "overflow")
    }

    func testMaxText() {
        XCTAssertEqual(AmountRules.text(units: 2_481_350_000), "2481.35")
        XCTAssertEqual(AmountRules.text(units: 1_000_000), "1")
        XCTAssertEqual(AmountRules.text(units: 1), "0.000001")
        XCTAssertEqual(AmountRules.text(units: 0), "0")
        XCTAssertEqual(check(AmountRules.text(units: 100_000_000)), .valid(100_000_000), "Max always passes its own check")
    }

    // MARK: Failures

    private func map(_ error: Error, units: UInt64 = 5_000_000, balance: UInt64 = 100_000_000) -> SendFailure {
        SendFailure.from(error, units: units, usdtBalance: balance)
    }

    func testMapsConnectionErrors() {
        XCTAssertEqual(map(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(map(URLError(.cannotFindHost)), .offline)
        XCTAssertEqual(map(URLError(.timedOut)), .outcomeUnknown, "a timeout may come after the broadcast")
        XCTAssertEqual(map(URLError(.networkConnectionLost)), .outcomeUnknown)
    }

    func testMapsTronClientFailures() {
        XCTAssertEqual(map(TronClient.Failure.rateLimited), .rateLimited)
        XCTAssertEqual(map(TronClient.Failure.badResponse), .outcomeUnknown)
        XCTAssertEqual(map(TronClient.Failure.http(503)), .outcomeUnknown)
        if case .rejected = map(TronClient.Failure.http(400)) {} else { XCTFail("4xx is a refusal") }
        XCTAssertEqual(map(WalletMissing()), .walletMissing)
        if case .unknown = map(CocoaError(.propertyListReadCorrupt)) {} else { XCTFail("other errors are unknown") }
    }

    func testMapsNetworkMessages() {
        func msg(_ text: String, units: UInt64 = 5_000_000) -> SendFailure {
            map(TronClient.Failure.rejected(text), units: units)
        }
        XCTAssertEqual(msg("Account resource insufficient error."), .insufficientTRX)
        XCTAssertEqual(msg("Not enough energy for 'PUSH1' operation executing"), .insufficientTRX)
        XCTAssertEqual(msg("Contract validate error : account [41ab] does not exist"), .insufficientTRX)
        XCTAssertEqual(msg("balance is not sufficient"), .insufficientTRX)
        XCTAssertEqual(msg("balance is not sufficient", units: 200_000_000), .insufficientUSDT)
        XCTAssertEqual(msg("REVERT opcode executed: transfer amount exceeds balance"), .insufficientUSDT)
        XCTAssertEqual(msg("Dup transaction."), .outcomeUnknown, "already on the network: never resend")
        XCTAssertEqual(msg("Validate signature error"), .rejected("Validate signature error"))
    }

    func testRetryOnlyWhenNothingWasSent() {
        XCTAssertTrue(SendFailure.offline.allowsRetry)
        XCTAssertTrue(SendFailure.rateLimited.allowsRetry)
        XCTAssertTrue(SendFailure.rejected("x").allowsRetry)
        XCTAssertFalse(SendFailure.outcomeUnknown.allowsRetry)
        XCTAssertFalse(SendFailure.unknown("x").allowsRetry)
        XCTAssertTrue(SendFailure.outcomeUnknown.mightHaveSent)
        XCTAssertFalse(SendFailure.insufficientTRX.mightHaveSent)
    }

    // MARK: Finding an unclear transfer

    func testMatchesOnlyANewTransferWithTheSameDetails() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let old = TokenTransfer(id: "old", date: start.addingTimeInterval(10), from: mine, to: valid, units: 5)
        let wrongAmount = TokenTransfer(id: "a", date: start.addingTimeInterval(20), from: mine, to: valid, units: 6)
        let tooEarly = TokenTransfer(id: "b", date: start.addingTimeInterval(-600), from: mine, to: valid, units: 5)
        let match = TokenTransfer(id: "c", date: start.addingTimeInterval(30), from: mine, to: valid, units: 5)
        let history = [old, wrongAmount, tooEarly, match]
        XCTAssertEqual(SendOutcome.match(in: history, from: mine, to: valid, units: 5, since: start, excluding: ["old"])?.id, "c")
        XCTAssertNil(SendOutcome.match(in: [old, wrongAmount, tooEarly], from: mine, to: valid, units: 5, since: start, excluding: ["old"]))
    }
}
