import Foundation

// MARK: - 还原结果

struct RestoreResult {
    let copiedFileCount: Int
    let failedItems: [FailedRestoreItem]
    let preSnapshotArchiveId: String?
    let elapsed: TimeInterval

    var hasErrors: Bool { !failedItems.isEmpty }
}

struct FailedRestoreItem {
    let relativePath: String
    let reason: String
}

// MARK: - 还原服务

struct RestoreService: Sendable {

    private let backupsRootURL: URL

    init(backupsRootURL: URL = AppPaths.defaultBackupsRootURL) {
        self.backupsRootURL = backupsRootURL
    }

    /// 执行还原
    /// - Parameters:
    ///   - archive: 要还原的存档
    ///   - createPreSnapshot: 还原前是否先创建快照（默认 true）
    func restore(
        archive: BackupArchive,
        createPreSnapshot: Bool = true
    ) async throws -> RestoreResult {
        let startTime = Date()
        var preSnapshotId: String? = nil

        // 1. 还原前快照
        if createPreSnapshot {
            preSnapshotId = try await createSnapshot(label: "pre-restore")
        }

        // 2. 执行还原
        let result = await performRestore(archive: archive, startTime: startTime, preSnapshotId: preSnapshotId)
        return result
    }

    // MARK: - 还原前快照

    private func createSnapshot(label: String) async throws -> String {
        let service = LocalBackupService(backupsRootURL: backupsRootURL)
        let request = BackupRequest(
            stateURL: OpenClawPaths.stateDirectory,
            workspaceURLs: OpenClawPaths.discoverWorkspaces().map { $0.url }.filter {
                FileManager.default.fileExists(atPath: $0.path)
            },
            label: label
        )
        let result = try await Task.detached(priority: .userInitiated) {
            try service.createManualBackup(request: request)
        }.value
        return result.meta.archiveId
    }

    // MARK: - 覆盖写入

    private func performRestore(
        archive: BackupArchive,
        startTime: Date,
        preSnapshotId: String?
    ) async -> RestoreResult {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let payloadURL = archive.payloadURL
            var copiedCount = 0
            var failedItems: [FailedRestoreItem] = []

            // payload 结构：payload/state/ 和 payload/workspaces/<name>/
            // 分别还原到对应的原始路径
            let statePayload = payloadURL.appendingPathComponent("state", isDirectory: true)
            let workspacesPayload = payloadURL.appendingPathComponent("workspaces", isDirectory: true)

            // 还原 state
            if fm.fileExists(atPath: statePayload.path) {
                let dest = OpenClawPaths.stateDirectory
                let (count, failures) = Self.copyDirectory(from: statePayload, to: dest, fm: fm)
                copiedCount += count
                failedItems.append(contentsOf: failures)
            }

            // 还原各 workspace
            if fm.fileExists(atPath: workspacesPayload.path),
               let wsItems = try? fm.contentsOfDirectory(
                   at: workspacesPayload,
                   includingPropertiesForKeys: [.isDirectoryKey],
                   options: [.skipsHiddenFiles]
               ) {
                // 找到对应的 workspace 目标路径
                let discoveredWorkspaces = OpenClawPaths.discoverWorkspaces()
                for wsItem in wsItems {
                    // 用 lastPathComponent 匹配 workspace 名称
                    let wsName = wsItem.lastPathComponent
                    let dest: URL
                    if let match = discoveredWorkspaces.first(where: { $0.url.lastPathComponent == wsName }) {
                        dest = match.url
                    } else {
                        // 没有匹配到，还原到 state 目录下同名 workspace
                        dest = OpenClawPaths.stateDirectory.appendingPathComponent("workspace-\(wsName)", isDirectory: true)
                    }
                    let (count, failures) = Self.copyDirectory(from: wsItem, to: dest, fm: fm)
                    copiedCount += count
                    failedItems.append(contentsOf: failures)
                }
            }

            return RestoreResult(
                copiedFileCount: copiedCount,
                failedItems: failedItems,
                preSnapshotArchiveId: preSnapshotId,
                elapsed: Date().timeIntervalSince(startTime)
            )
        }.value
    }

    // MARK: - 目录复制（原子替换）

    private static func copyDirectory(
        from sourceURL: URL,
        to destURL: URL,
        fm: FileManager
    ) -> (copiedCount: Int, failures: [FailedRestoreItem]) {
        var copiedCount = 0
        var failures: [FailedRestoreItem] = []

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: []
        ) else { return (0, []) }

        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { continue }

            let relative = itemURL.path.replacingOccurrences(of: sourceURL.path + "/", with: "")
            let targetURL = destURL.appendingPathComponent(relative)

            if values.isDirectory == true {
                try? fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                do {
                    // 确保父目录存在
                    try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    // 原子替换：先写临时文件再 replace
                    let tempURL = targetURL.deletingLastPathComponent()
                        .appendingPathComponent(".\(UUID().uuidString).tmp")
                    try fm.copyItem(at: itemURL, to: tempURL)
                    _ = try fm.replaceItemAt(targetURL, withItemAt: tempURL)
                    copiedCount += 1
                } catch {
                    failures.append(FailedRestoreItem(relativePath: relative, reason: error.localizedDescription))
                }
            }
        }

        return (copiedCount, failures)
    }
}

// MARK: - 错误

enum RestoreError: LocalizedError {
    case payloadNotFound
    case snapshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .payloadNotFound: return "备份 payload 目录不存在，无法还原"
        case .snapshotFailed(let msg): return "还原前快照创建失败：\(msg)"
        }
    }
}
