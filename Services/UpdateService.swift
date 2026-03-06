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

// MARK: - Service

actor UpdateService {
    static let shared = UpdateService()

    private let apiURL = URL(string: "https://api.github.com/repos/Geoion/BackClaw/releases/latest")!

    /// Fetches the latest GitHub release and returns it if it is newer than the running app version.
    /// Returns `nil` when the app is already up to date or the check cannot be completed.
    func checkForUpdates() async throws -> AppRelease? {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let name = json["name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let htmlURL = URL(string: htmlURLString) else {
            return nil
        }

        let body = json["body"] as? String ?? ""
        let release = AppRelease(tagName: tagName, name: name, body: body, htmlURL: htmlURL)

        let currentVersion = AppPaths.appVersion
        guard isNewer(version: release.version, than: currentVersion) else {
            return nil
        }

        return release
    }

    // MARK: - Version comparison

    private func isNewer(version: String, than current: String) -> Bool {
        let newParts = version.split(separator: ".").compactMap { Int($0) }
        let curParts = current.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(newParts.count, curParts.count)
        for i in 0..<maxLen {
            let nv = i < newParts.count ? newParts[i] : 0
            let cv = i < curParts.count ? curParts[i] : 0
            if nv != cv { return nv > cv }
        }
        return false
    }
}
