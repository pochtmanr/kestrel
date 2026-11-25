import XCTest
@testable import Kestrel

final class ReceiveTests: XCTestCase {
    private let me = "TV2QjYfd8Js2JhDfqKzZMLBscYtBkxU9ek"
    private let other = "TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7"

    // MARK: Payment payload

    func testNoAmountIsTheBareAddress() {
        XCTAssertEqual(ReceiveLogic.paymentPayload(address: me, token: .usdt, units: nil), me)
        XCTAssertEqual(ReceiveLogic.paymentPayload(address: me, token: .usdt, units: 0), me)
        XCTAssertEqual(ReceiveLogic.paymentPayload(address: me, token: .trx, units: nil), me)
    }

    func testUSDTRequestCarriesTheContract() {
        XCTAssertEqual(ReceiveLogic.paymentPayload(address: me, token: .usdt, units: 50_500_000),
                       "tron:\(me)?amount=50.5&token=TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t")
    }

    func testTRXRequestNamesTheCoin() {
        XCTAssertEqual(ReceiveLogic.paymentPayload(address: me, token: .trx, units: 25_000_000),
                       "tron:\(me)?amount=25&token=TRX")
    }

    func testOwnScannerReadsUSDTRequestBack() throws {
        let uri = ReceiveLogic.paymentPayload(address: me, token: .usdt, units: 50_500_000)
        let request = try XCTUnwrap(PaymentRequest.parse(uri))
        XCTAssertEqual(request.address, me)
        XCTAssertEqual(request.amount, "50.5")
        XCTAssertFalse(request.otherToken)
    }

    func testOwnScannerNeverReadsTRXRequestAsUSDT() throws {
        let uri = ReceiveLogic.paymentPayload(address: me, token: .trx, units: 25_000_000)
        let request = try XCTUnwrap(PaymentRequest.parse(uri))
        XCTAssertEqual(request.address, me)
        XCTAssertTrue(request.otherToken)
        XCTAssertNil(request.amount)
    }

    func testDecimalAmount() {
        XCTAssertEqual(ReceiveLogic.decimalAmount(50_000_000), "50")
        XCTAssertEqual(ReceiveLogic.decimalAmount(1), "0.000001")
        XCTAssertEqual(ReceiveLogic.decimalAmount(1_234_567_890), "1234.56789")
    }

    // MARK: Amount input

    func testParseAmount() {
        XCTAssertEqual(ReceiveLogic.parseAmount(""), .empty)
        XCTAssertEqual(ReceiveLogic.parseAmount("  "), .empty)
        XCTAssertEqual(ReceiveLogic.parseAmount("12.5"), .valid(12_500_000))
        XCTAssertEqual(ReceiveLogic.parseAmount("12,5"), .valid(12_500_000), "comma decimal separator")
        XCTAssertEqual(ReceiveLogic.parseAmount(".5"), .valid(500_000))
        XCTAssertEqual(ReceiveLogic.parseAmount("0"), .zero)
        XCTAssertEqual(ReceiveLogic.parseAmount("0.000"), .zero)
        XCTAssertEqual(ReceiveLogic.parseAmount("1.1234567"), .tooManyDecimals)
        XCTAssertEqual(ReceiveLogic.parseAmount("abc"), .invalid)
        XCTAssertEqual(ReceiveLogic.parseAmount("1.2.3"), .invalid)
        XCTAssertEqual(ReceiveLogic.parseAmount("-5"), .invalid)
        XCTAssertEqual(ReceiveLogic.parseAmount("10000000001"), .tooLarge)
        XCTAssertEqual(ReceiveLogic.parseAmount("99999999999999999999"), .tooLarge, "overflow")
    }

    // MARK: Address groups

    func testAddressGroupsOfFour() {
        let groups = ReceiveLogic.addressGroups(me)
        XCTAssertEqual(groups.count, 9)
        XCTAssertEqual(groups.first, "TV2Q")
        XCTAssertEqual(groups.last, "ek")
        XCTAssertEqual(groups.joined(), me, "nothing lost or reordered")
        XCTAssertEqual(ReceiveLogic.addressGroups(""), [])
    }

    // MARK: Incoming detection

    private func transfer(_ id: String, from: String, to: String, units: UInt64 = 1_000_000, age: TimeInterval = 0) -> TokenTransfer {
        TokenTransfer(id: id, date: Date(timeIntervalSince1970: 1_700_000_000 - age), from: from, to: to, units: units)
    }

    func testNothingBeforeTheHistoryLoads() {
        var watch = IncomingWatch()
        let old = [transfer("a", from: other, to: me)]
        XCTAssertEqual(watch.observe(history: [], trxSun: 0, myAddress: me, loaded: false, watchTRX: true), [])
        // The first load is the baseline, not 25 new payments.
        XCTAssertEqual(watch.observe(history: old, trxSun: 5, myAddress: me, loaded: true, watchTRX: true), [])
        XCTAssertEqual(watch.observe(history: old, trxSun: 5, myAddress: me, loaded: true, watchTRX: true), [])
    }

    func testNewIncomingTransferIsReportedOnce() {
        var watch = IncomingWatch()
        let old = transfer("a", from: other, to: me, age: 100)
        _ = watch.observe(history: [old], trxSun: 0, myAddress: me, loaded: true, watchTRX: true)
        let new = transfer("b", from: other, to: me, units: 50_000_000)
        XCTAssertEqual(watch.observe(history: [new, old], trxSun: 0, myAddress: me, loaded: true, watchTRX: true), [.usdt(new)])
        XCTAssertEqual(watch.observe(history: [new, old], trxSun: 0, myAddress: me, loaded: true, watchTRX: true), [])
    }

    func testOutgoingAndSelfTransfersAreIgnored() {
        var watch = IncomingWatch()
        _ = watch.observe(history: [], trxSun: 0, myAddress: me, loaded: true, watchTRX: true)
        let sent = transfer("s", from: me, to: other)
        let toSelf = transfer("x", from: me, to: me)
        XCTAssertEqual(watch.observe(history: [sent, toSelf], trxSun: 0, myAddress: me, loaded: true, watchTRX: true), [])
    }

    func testSeveralNewComeNewestFirst() {
        var watch = IncomingWatch()
        _ = watch.observe(history: [], trxSun: 0, myAddress: me, loaded: true, watchTRX: true)
        let older = transfer("1", from: other, to: me, age: 60)
        let newer = transfer("2", from: other, to: me, age: 0)
        XCTAssertEqual(watch.observe(history: [older, newer], trxSun: 0, myAddress: me, loaded: true, watchTRX: true),
                       [.usdt(newer), .usdt(older)])
    }

    func testIdThatScrolledOutOfTheWindowDoesntComeBack() {
        var watch = IncomingWatch()
        let a = transfer("a", from: other, to: me)
        _ = watch.observe(history: [a], trxSun: 0, myAddress: me, loaded: true, watchTRX: true)
        _ = watch.observe(history: [], trxSun: 0, myAddress: me, loaded: true, watchTRX: true)
        XCTAssertEqual(watch.observe(history: [a], trxSun: 0, myAddress: me, loaded: true, watchTRX: true), [])
    }

    func testTRXIncreaseAndBaselineReset() {
        var watch = IncomingWatch()
        _ = watch.observe(history: [], trxSun: 10_000_000, myAddress: me, loaded: true, watchTRX: true)
        XCTAssertEqual(watch.observe(history: [], trxSun: 35_000_000, myAddress: me, loaded: true, watchTRX: true),
                       [.trx(sun: 25_000_000)])
        // Fees paid: the balance drops, then a top-up counts from the lower balance.
        XCTAssertEqual(watch.observe(history: [], trxSun: 20_000_000, myAddress: me, loaded: true, watchTRX: true), [])
        XCTAssertEqual(watch.observe(history: [], trxSun: 30_000_000, myAddress: me, loaded: true, watchTRX: true),
                       [.trx(sun: 10_000_000)])
    }

    func testTRXIgnoredWhenNotWatched() {
        var watch = IncomingWatch()
        _ = watch.observe(history: [], trxSun: 0, myAddress: me, loaded: true, watchTRX: false)
        XCTAssertEqual(watch.observe(history: [], trxSun: 9, myAddress: me, loaded: true, watchTRX: false), [])
    }
}
