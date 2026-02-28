import AppKit
import Foundation

/// 管理 security-scoped bookmark，持久化对用户目录的访问权限。
/// 使用 actor 保证并发安全。
actor BookmarkManager {
    static let shared = BookmarkManager()

    private var accessingURLs: [String: URL] = [:]

    private init() {}

    // MARK: - Bookmark 存取

    func hasBookmark(for key: String) -> Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    func resolveBookmark(for key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { saveBookmark(for: url, key: key) }
            return url
        } catch {
            return nil
        }
    }

    @discardableResult
    func saveBookmark(for url: URL, key: String) -> Bool {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: key)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 访问控制

    @discardableResult
    func startAccessing(_ url: URL, key: String) -> Bool {
        stopAccessing(key: key)
        let success = url.startAccessingSecurityScopedResource()
        if success { accessingURLs[key] = url }
        return success
    }

    func stopAccessing(key: String) {
        accessingURLs[key]?.stopAccessingSecurityScopedResource()
        accessingURLs.removeValue(forKey: key)
    }

    func stopAll() {
        for (_, url) in accessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessingURLs.removeAll()
    }

    // MARK: - 授权弹窗（必须在 MainActor 调用）

    @MainActor
    func requestAccess(
        title: String,
        message: String,
        defaultURL: URL,
        key: String
    ) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = defaultURL

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        await saveBookmark(for: url, key: key)
        return url
    }
}

// MARK: - OpenClaw 专用便捷方法

extension BookmarkManager {
    static let openClawStateKey = "openclawStateBookmark"

    func resolveOpenClawStateAccess() async -> URL? {
        guard let url = resolveBookmark(for: Self.openClawStateKey) else { return nil }
        guard startAccessing(url, key: Self.openClawStateKey) else { return nil }
        return url
    }

    @MainActor
    func requestOpenClawStateAccess() async -> URL? {
        let defaultURL = OpenClawPaths.stateDirectory
        guard let url = await requestAccess(
            title: "选择 OpenClaw 数据目录",
            message: "BackClaw 需要访问 OpenClaw 的数据目录（~/.openclaw）才能执行备份。请选择该目录以授权。",
            defaultURL: defaultURL,
            key: Self.openClawStateKey
        ) else { return nil }
        guard await startAccessing(url, key: Self.openClawStateKey) else { return nil }
        return url
    }
}
