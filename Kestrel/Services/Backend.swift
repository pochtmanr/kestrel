import Foundation

/// The Simnetiq backend (Supabase): edge functions and PostgREST tables for
/// wallet features that need a server, such as push notifications for incoming
/// transfers or address-book sync. The wallet itself never needs it:
/// balances and sends go straight to TronGrid, and nothing sent here may
/// include the recovery phrase, keys or PIN.
///
/// Calls are anonymous (anon key) unless a caller passes a user access token.
struct Backend: Sendable {
    static let projectURL = URL(string: "https://supabase.holylabs.net")!
    /// Public anon key: it only identifies the project. Row-level security
    /// and the edge functions decide what a caller may do.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzY3ODgwODQyLCJleHAiOjIwODM0NTY4NDJ9.10n-Cr7kuYq_SYT185LBB_7YQv9WXwxyn-dYDX6DSaU"

    var session: URLSession = .shared

    struct Failure: LocalizedError {
        let status: Int
        let message: String?
        var errorDescription: String? {
            message ?? tr("Something went wrong. Please try again.")
        }
    }

    // MARK: Edge functions

    /// `POST functions/v1/<name>` with a JSON body, decoding the JSON reply.
    func invoke<Body: Encodable, Reply: Decodable>(
        _ function: String, body: Body, token: String? = nil, as reply: Reply.Type = Reply.self
    ) async throws -> Reply {
        var request = request(Self.projectURL.appending(path: "functions/v1/\(function)"), token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    // MARK: Tables (PostgREST)

    /// `GET rest/v1/<table>?<query>`, e.g. `["select": "*", "address": "eq.T…"]`.
    func select<Row: Decodable>(
        _ table: String, query: [String: String] = ["select": "*"], token: String? = nil, as row: Row.Type = Row.self
    ) async throws -> [Row] {
        var components = URLComponents(url: Self.projectURL.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await send(request(components.url!, token: token))
    }

    /// `POST rest/v1/<table>`: insert (or upsert, with `upsert: true`) rows.
    func insert<Row: Encodable>(_ table: String, _ rows: [Row], upsert: Bool = false, token: String? = nil) async throws {
        var request = request(Self.projectURL.appending(path: "rest/v1/\(table)"), token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(upsert ? "resolution=merge-duplicates,return=minimal" : "return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(rows)
        _ = try await data(for: request)
    }

    // MARK: Plumbing

    private func request(_ url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? Self.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<Reply: Decodable>(_ request: URLRequest) async throws -> Reply {
        let data = try await data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
            }
            return date
        }
        return try decoder.decode(Reply.self, from: data)
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Edge functions reply {error}; PostgREST replies {message}.
            struct Reply: Decodable { let error: String?; let message: String? }
            let reply = try? JSONDecoder().decode(Reply.self, from: data)
            throw Failure(status: status, message: reply?.error ?? reply?.message)
        }
        return data
    }
}
