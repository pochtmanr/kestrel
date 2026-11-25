import XCTest
@testable import Kestrel

/// Offline checks for the Activity history: TronGrid row parsing, merging,
/// the on-disk cache and the demo data.
@MainActor
final class ActivityStoreTests: XCTestCase {
    private let me = "TV2QjYfd8Js2JhDfqKzZMLBscYtBkxU9ek"

    private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: Parsing

    func testParseTransfersWithNextPage() throws {
        let body = try json("""
        {"data":[
          {"transaction_id":"aa","token_info":{"symbol":"USDT"},"block_timestamp":1764517689000,
           "from":"TEPSrSYPDSQ7yXpMFPq91Fb1QEWpMkRGfn","to":"TMuA6YqfCeX8EhbfYEg5y7S4DqzSJireY9",
           "type":"Transfer","value":"2000000"},
          {"transaction_id":"bb","block_timestamp":1738487667000,"from":"TMuA6YqfCeX8EhbfYEg5y7S4DqzSJireY9",
           "to":"TYNZzWMwpRjspHhbEikfKaXhsam8NMPMmm","value":"1100000"},
          {"transaction_id":"broken","block_timestamp":1738487667000,"from":"x","to":"y","value":"-1"}
        ],"success":true,"meta":{"at":1795615970729,"fingerprint":"Cndjyb3v","page_size":3}}
        """)
        let page = TronClient.parseTransfers(body)
        XCTAssertEqual(page.next, "Cndjyb3v")
        XCTAssertEqual(page.transfers.map(\.id), ["aa", "bb"])
        XCTAssertEqual(page.transfers[0].units, 2_000_000)
        XCTAssertEqual(page.transfers[0].date, Date(timeIntervalSince1970: 1_764_517_689))
        XCTAssertEqual(page.transfers[1].to, "TYNZzWMwpRjspHhbEikfKaXhsam8NMPMmm")
    }

    func testParseTransfersLastPage() throws {
        let body = try json("""
        {"data":[{"transaction_id":"aa","block_timestamp":1,"from":"a","to":"b","value":"5"}],
         "success":true,"meta":{"at":1795615970729,"page_size":1}}
        """)
        let page = TronClient.parseTransfers(body)
        XCTAssertNil(page.next)
        XCTAssertEqual(page.transfers.count, 1)
        XCTAssertNil(TronClient.parseTransfers(try json(#"{"data":[],"meta":{"fingerprint":""}}"#)).next)
    }

    func testParseFees() throws {
        let body = try json("""
        {"data":[
          {"txID":"usdt","ret":[{"contractRet":"SUCCESS","fee":13845850}],"energy_fee":13499850,"net_fee":346000},
          {"txID":"free","ret":[{"contractRet":"SUCCESS","fee":0}],"energy_fee":0,"net_fee":0},
          {"txID":"noret","energy_fee":2785230,"net_fee":346000},
          {"ret":[{"fee":5}]}
        ],"success":true,"meta":{"fingerprint":"2NgPQ","page_size":4}}
        """)
        let page = TronClient.parseFees(body)
        XCTAssertEqual(page.next, "2NgPQ")
        XCTAssertEqual(page.fees, ["usdt": 13_845_850, "free": 0, "noret": 3_131_230])

        let last = TronClient.parseFees(try json(#"{"data":[{"txID":"a","ret":[{"fee":1}]}],"meta":{"page_size":1}}"#))
        XCTAssertNil(last.next)
        XCTAssertEqual(last.fees, ["a": 1])
    }

    // MARK: Merge

    func testMergeDedupesAndSortsNewestFirst() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        func transfer(_ id: String, _ offset: TimeInterval, units: UInt64 = 1) -> TokenTransfer {
            TokenTransfer(id: id, date: t0.addingTimeInterval(offset), from: "a", to: "b", units: units)
        }
        let existing = [transfer("c", 30), transfer("b", 20), transfer("a", 10)]
        let new = [transfer("d", 40), transfer("b", 20, units: 9), transfer("e", 20)]
        let merged = ActivityStore.merge(new, into: existing)
        XCTAssertEqual(merged.map(\.id), ["d", "c", "e", "b", "a"])
        XCTAssertEqual(merged.first { $0.id == "b" }?.units, 9)
        XCTAssertEqual(ActivityStore.merge([], into: existing.reversed()).map(\.id), ["c", "b", "a"])
    }

    // MARK: Cache

    func testCacheRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "activity-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshot = ActivityStore.Snapshot(
            address: me,
            transfers: [TokenTransfer(id: "x", date: Date(timeIntervalSince1970: 1_700_000_000.5), from: me, to: "b", units: 42)],
            fees: ["x": 13_000_000],
            coveredSince: .distantPast,
            reachedStart: true
        )
        ActivityStore.save(snapshot, in: dir)
        XCTAssertEqual(ActivityStore.load(address: me, in: dir), snapshot)
        XCTAssertNil(ActivityStore.load(address: "TMuA6YqfCeX8EhbfYEg5y7S4DqzSJireY9", in: dir))

        let store = ActivityStore(directory: dir)
        store.configure(address: me)
        XCTAssertEqual(store.transfers, snapshot.transfers)
        XCTAssertEqual(store.fees, snapshot.fees)
        XCTAssertTrue(store.reachedStart)
        XCTAssertTrue(store.isComplete(since: nil))

        store.configure(address: nil)
        XCTAssertTrue(store.transfers.isEmpty)
        XCTAssertFalse(store.isComplete(since: .now))

        store.configure(address: me)
        store.clear()
        await store.flush()
        XCTAssertTrue(store.transfers.isEmpty)
        XCTAssertNil(ActivityStore.load(address: me, in: dir))
    }

    // MARK: Demo

    func testDemoHistoryIsDeterministicAndNeverNegative() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let store = ActivityStore(directory: FileManager.default.temporaryDirectory.appending(path: "unused-\(UUID().uuidString)"))
        store.loadDemo(address: me, now: now)
        let transfers = store.transfers
        XCTAssertTrue((70 ... 100).contains(transfers.count), "\(transfers.count) transfers")
        XCTAssertTrue(store.reachedStart)
        XCTAssertEqual(store.coveredSince, .distantPast)
        XCTAssertEqual(Set(transfers.map(\.id)).count, transfers.count)

        let again = ActivityStore.demoHistory(address: me, now: now)
        XCTAssertEqual(ActivityStore.merge(again.transfers, into: []), transfers)
        XCTAssertEqual(again.fees, store.fees)

        let span = try XCTUnwrap(transfers.first?.date).timeIntervalSince(try XCTUnwrap(transfers.last?.date))
        XCTAssertTrue((380 ... 460).contains(span / 86_400), "spans \(span / 86_400) days")

        var balance: Int64 = 0
        for transfer in transfers.reversed() {
            let incoming = transfer.to == me
            XCTAssertTrue(incoming || transfer.from == me)
            XCTAssertTrue((5_000_000 ... 3_000_000_000).contains(transfer.units), "\(transfer.units) units")
            balance += incoming ? Int64(transfer.units) : -Int64(transfer.units)
            XCTAssertGreaterThanOrEqual(balance, 0)
            if incoming {
                XCTAssertNil(store.fees[transfer.id])
            } else {
                let fee = try XCTUnwrap(store.fees[transfer.id])
                XCTAssertTrue((13_000_000 ... 28_000_000).contains(fee))
            }
        }
        XCTAssertEqual(balance, 2_481_350_000)
        XCTAssertEqual(transfers.first?.id, "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2")
        XCTAssertEqual(Set(transfers.flatMap { [$0.from, $0.to] }).count, 7)
        XCTAssertNil(ActivityStore.load(address: me, in: FileManager.default.temporaryDirectory))
    }
}
