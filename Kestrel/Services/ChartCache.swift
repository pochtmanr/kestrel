import Foundation

/// Price charts kept on disk, so the coin screen can draw one before the
/// network answers, and the five-year chart is fetched once a day at most.
///
/// Only public market prices are stored, keyed by coin and range: nothing
/// about the wallet (no address, no balance). The files live in Caches, which
/// the system may empty at any time; a missing file just means a fetch.
enum ChartCache {
    private struct Snapshot: Codable {
        var version = 1
        var fetched: Date
        var points: [PricePoint]
    }

    /// `directory` nil = Caches (tests pass a temp folder).
    nonisolated static func load(token: TokenKind, range: PriceRange, in directory: URL? = nil) -> (points: [PricePoint], fetched: Date)? {
        guard let url = cacheURL(token: token, range: range, in: directory), let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1, !snapshot.points.isEmpty
        else { return nil }
        return (snapshot.points, snapshot.fetched)
    }

    nonisolated static func save(
        _ points: [PricePoint], token: TokenKind, range: PriceRange, in directory: URL? = nil, fetched: Date = .now
    ) {
        guard !points.isEmpty, let url = cacheURL(token: token, range: range, in: directory) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Snapshot(fetched: fetched, points: points)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated static func cacheURL(token: TokenKind, range: PriceRange, in directory: URL? = nil) -> URL? {
        let directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return directory?.appending(path: "chart-\(token.rawValue)-\(range.rawValue).json")
    }
}
