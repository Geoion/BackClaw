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
    private let changelogURL = URL(string: "https://raw.githubusercontent.com/Geoion/BackClaw/main/CHANGELOG.md")!

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

        let currentVersion = AppPaths.appVersion
        let apiBody = json["body"] as? String ?? ""

        let candidateRelease = AppRelease(tagName: tagName, name: name, body: apiBody, htmlURL: htmlURL)
        guard isNewer(version: candidateRelease.version, than: currentVersion) else {
            return nil
        }

        // Prefer the changelog section from CHANGELOG.md on GitHub so that users on
        // older app versions (which don't have the local file) still see up-to-date notes.
        let changelogBody = await fetchChangelogSection(for: tagName)
        let body = changelogBody ?? apiBody
        return AppRelease(tagName: tagName, name: name, body: body, htmlURL: htmlURL)
    }

    // MARK: - CHANGELOG fetch

    /// Downloads CHANGELOG.md from GitHub and extracts the section for `tagName`.
    /// Returns `nil` if the network request fails or the section is not found.
    private func fetchChangelogSection(for tagName: String) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: changelogURL),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        return extractSection(from: content, tagName: tagName)
    }

    /// Extracts the Markdown section for `tagName` from a CHANGELOG string.
    /// Sections are delimited by `## ` headings; the version heading is expected to
    /// start with the tag name (with or without a leading `v`), e.g. `## v1.1.0`.
    func extractSection(from changelog: String, tagName: String) -> String? {
        let normalizedTag = tagName.hasPrefix("v") ? tagName : "v\(tagName)"
        let lines = changelog.components(separatedBy: "\n")

        var insideSection = false
        var sectionLines: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                if insideSection { break }
                // Match heading like "## v1.1.0" or "## v1.1.0 — date"
                let heading = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if heading == normalizedTag || heading.hasPrefix(normalizedTag + " ") || heading.hasPrefix(normalizedTag + "\t") {
                    insideSection = true
                }
                continue
            }
            if insideSection {
                sectionLines.append(line)
            }
        }

        if sectionLines.isEmpty { return nil }

        // Trim leading/trailing blank lines
        var result = sectionLines
        while result.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeFirst() }
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeLast() }
        return result.isEmpty ? nil : result.joined(separator: "\n")
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
