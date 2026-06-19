import Foundation

// MARK: - Wire models (claude.ai internal API)
//
// Every field is optional on purpose: this is a private, undocumented endpoint
// that "may change without notice," so a missing or renamed key must degrade
// gracefully (that window just doesn't show) rather than throw out the whole
// payload. This mirrors the previous hand-rolled dictionary parser exactly.
struct UsageWindowDTO: Decodable {
    let utilization: Double?
    let resets_at: String?
}

struct UsageResponseDTO: Decodable {
    let five_hour: UsageWindowDTO?
    let seven_day: UsageWindowDTO?
    let seven_day_sonnet: UsageWindowDTO?
}

struct BootstrapDTO: Decodable {
    struct Account: Decodable { let lastActiveOrgId: String? }
    let account: Account?
}

// MARK: - Domain models

/// A single parsed usage window: integer utilization (0–100) and optional reset.
struct WindowUsage {
    var utilization: Int
    var resetsAt: Date?
}

/// The result of parsing a usage response. Any window may be absent.
struct ParsedUsage {
    var session: WindowUsage?
    var weekly: WindowUsage?
    var weeklySonnet: WindowUsage?
}

/// Persisted snapshot of the last successful fetch, so the UI and menu-bar icon
/// can render immediately on launch instead of showing 0% until the network
/// round-trip completes.
struct UsageSnapshot: Codable {
    var sessionUsage: Int
    var weeklyUsage: Int
    var weeklySonnetUsage: Int
    var hasWeeklySonnet: Bool
    var sessionResetsAt: Date?
    var weeklyResetsAt: Date?
    var weeklySonnetResetsAt: Date?
    var lastUpdated: Date
}

// MARK: - Errors

enum APIError: Error {
    case offline          // transport failure (no connection / timeout)
    case authExpired      // 401 / 403 — cookie expired or revoked
    case http(Int)        // other non-success status
    case invalidResponse  // not an HTTP response
    case decoding         // body wasn't the JSON we expected
    case noOrgId          // couldn't determine the organization id

    var userMessage: String {
        switch self {
        case .offline:         return "Offline — showing last known usage"
        case .authExpired:     return "Session expired — please sign in again"
        case .http(let code):  return "HTTP \(code)"
        case .invalidResponse: return "Invalid response"
        case .decoding:        return "Couldn't read usage data"
        case .noOrgId:         return "Could not get org ID from session"
        }
    }
}

// MARK: - Lenient ISO8601 parsing

enum ISO8601 {
    // claude.ai timestamps usually carry fractional seconds, but don't assume it —
    // fall back to the plain internet-date format so reset times never silently
    // vanish if the format shifts.
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return withFraction.date(from: string) ?? withoutFraction.date(from: string)
    }
}
