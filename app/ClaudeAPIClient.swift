import Foundation

// MARK: - claude.ai usage API client
//
// Owns all networking and parsing. Resolves the organization id (from the
// session cookie, falling back to /api/bootstrap), then fetches usage. Transient
// failures (offline, 5xx) are retried with backoff; auth failures are not.
struct ClaudeAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Full pipeline: resolve org id → fetch usage → parse.
    func fetchUsage(cookie: String) async -> Result<ParsedUsage, APIError> {
        guard let orgId = await resolveOrgId(cookie: cookie) else {
            return .failure(.noOrgId)
        }

        let urlString = "https://claude.ai/api/organizations/\(orgId)/usage"
        guard let url = URL(string: urlString) else { return .failure(.invalidResponse) }

        switch await get(url, cookie: cookie) {
        case .failure(let err):
            return .failure(err)
        case .success(let data):
            guard let dto = try? JSONDecoder().decode(UsageResponseDTO.self, from: data) else {
                return .failure(.decoding)
            }
            return .success(parse(dto))
        }
    }

    // MARK: Org id

    private func resolveOrgId(cookie: String) async -> String? {
        // Fast path: the org id is usually in the lastActiveOrg cookie value.
        if let fromCookie = orgIdFromCookie(cookie) { return fromCookie }

        // Fallback: ask the bootstrap endpoint.
        guard let url = URL(string: "https://claude.ai/api/bootstrap") else { return nil }
        guard case .success(let data) = await get(url, cookie: cookie),
              let dto = try? JSONDecoder().decode(BootstrapDTO.self, from: data) else {
            return nil
        }
        return dto.account?.lastActiveOrgId
    }

    private func orgIdFromCookie(_ cookie: String) -> String? {
        for part in cookie.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                return String(trimmed.dropFirst("lastActiveOrg=".count))
            }
        }
        return nil
    }

    // MARK: Request + retry

    private func get(_ url: URL, cookie: String) async -> Result<Data, APIError> {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // sessionCookie is already the full cookie header — send it as-is.
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("claude.ai", forHTTPHeaderField: "authority")

        let maxAttempts = 3
        for attempt in 0..<maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return .failure(.invalidResponse)
                }
                switch http.statusCode {
                case 200:
                    return .success(data)
                case 401, 403:
                    return .failure(.authExpired)   // never retry auth failures
                case 500...599:
                    if attempt < maxAttempts - 1 {
                        await backoff(attempt)
                        continue
                    }
                    return .failure(.http(http.statusCode))
                default:
                    return .failure(.http(http.statusCode))
                }
            } catch {
                if attempt < maxAttempts - 1 {
                    await backoff(attempt)
                    continue
                }
                return .failure(.offline)
            }
        }
        return .failure(.offline)
    }

    /// Exponential-ish backoff: 0.5s, then 1s.
    private func backoff(_ attempt: Int) async {
        let seconds = 0.5 * pow(2.0, Double(attempt))
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: Parsing

    private func parse(_ dto: UsageResponseDTO) -> ParsedUsage {
        func window(_ w: UsageWindowDTO?) -> WindowUsage? {
            guard let w else { return nil }
            return WindowUsage(
                utilization: Int(w.utilization ?? 0),
                resetsAt: ISO8601.date(from: w.resets_at)
            )
        }
        return ParsedUsage(
            session: window(dto.five_hour),
            weekly: window(dto.seven_day),
            weeklySonnet: window(dto.seven_day_sonnet)
        )
    }
}
