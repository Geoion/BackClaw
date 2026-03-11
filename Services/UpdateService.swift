import Foundation

// MARK: - Model

struct AppRelease: Sendable {
    let tagName: String
    let name: String
    let body: String
    let htmlURL: URL

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

enum UpdateCheckTrigger: Sendable {
    case automatic
    case manual
}

enum UpdateCheckFailure: Error, Sendable {
    case rateLimited(resetAt: Date?)
    case network(description: String)
    case invalidResponse
    case server(statusCode: Int)
    case invalidPayload
}

enum UpdateCheckStatus: Sendable {
    case updateAvailable(AppRelease)
    case upToDate
    case skipped
    case failed(UpdateCheckFailure)
}

// MARK: - Service

actor UpdateService {
    static let shared = UpdateService()

    private let apiURL = URL(string: "https://api.github.com/repos/Geoion/BackClaw/releases/latest")!
    private let autoCheckInterval: TimeInterval = 6 * 60 * 60
    private let autoCheckLastAttemptAtKey = "update.auto.lastAttemptAt"
    private let decoder = JSONDecoder()

    /// Checks GitHub for updates and returns a structured result.
    func checkForUpdates(trigger: UpdateCheckTrigger) async -> UpdateCheckStatus {
        if trigger == .automatic, shouldSkipAutomaticCheck(now: Date()) {
            return .skipped
        }
        if trigger == .automatic {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: autoCheckLastAttemptAtKey)
        }

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("BackClaw/\(AppPaths.appVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failed(.network(description: error.localizedDescription))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failed(.invalidResponse)
        }

        if httpResponse.statusCode == 403, isRateLimited(response: httpResponse, data: data) {
            return .failed(.rateLimited(resetAt: rateLimitResetDate(from: httpResponse)))
        }

        guard httpResponse.statusCode == 200 else {
            return .failed(.server(statusCode: httpResponse.statusCode))
        }

        guard let payload = try? decoder.decode(GitHubReleasePayload.self, from: data),
              let htmlURL = URL(string: payload.htmlURLString) else {
            return .failed(.invalidPayload)
        }
        let releaseName = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let release = AppRelease(
            tagName: payload.tagName,
            name: releaseName.isEmpty ? payload.tagName : releaseName,
            body: payload.body ?? "",
            htmlURL: htmlURL
        )

        return isNewer(version: release.version, than: AppPaths.appVersion)
            ? .updateAvailable(release)
            : .upToDate
    }

    // MARK: - Version comparison

    private func isNewer(version: String, than current: String) -> Bool {
        let newVersion = parseVersion(version)
        let currentVersion = parseVersion(current)
        let newParts = newVersion.parts
        let curParts = currentVersion.parts
        let maxLen = max(newParts.count, curParts.count)
        for i in 0..<maxLen {
            let nv = i < newParts.count ? newParts[i] : 0
            let cv = i < curParts.count ? curParts[i] : 0
            if nv != cv { return nv > cv }
        }
        // 相同数字版本时，正式版 > 预发布版（例如 1.2.0 > 1.2.0-beta1）
        if newVersion.hasPrerelease != currentVersion.hasPrerelease {
            return !newVersion.hasPrerelease && currentVersion.hasPrerelease
        }
        return false
    }

    private func parseVersion(_ version: String) -> (parts: [Int], hasPrerelease: Bool) {
        let normalized = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let noVPrefix = normalized.hasPrefix("v") || normalized.hasPrefix("V")
            ? String(normalized.dropFirst())
            : normalized
        let chunks = noVPrefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = chunks.first.map(String.init) ?? noVPrefix
        let hasPrerelease = chunks.count > 1
        let parts = core.split(separator: ".").map { segment in
            Int(segment.prefix { $0.isNumber }) ?? 0
        }
        return (parts, hasPrerelease)
    }

    private func shouldSkipAutomaticCheck(now: Date) -> Bool {
        let last = UserDefaults.standard.double(forKey: autoCheckLastAttemptAtKey)
        guard last > 0 else { return false }
        return now.timeIntervalSince1970 - last < autoCheckInterval
    }

    private func isRateLimited(response: HTTPURLResponse, data: Data) -> Bool {
        if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
            return true
        }
        if let err = try? decoder.decode(GitHubErrorPayload.self, from: data),
           let message = err.message?.lowercased(),
           message.contains("rate limit") {
            return true
        }
        return false
    }

    private func rateLimitResetDate(from response: HTTPURLResponse) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let timestamp = TimeInterval(raw) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
}

// MARK: - GitHub Payload

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURLString: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURLString = "html_url"
    }
}

private struct GitHubErrorPayload: Decodable {
    let message: String?
}
