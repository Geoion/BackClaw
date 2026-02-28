import Foundation

// MARK: - 备份请求

struct BackupRequest: Sendable {
    let stateURL: URL
    let workspaceURLs: [URL]
    let label: String?

    var allSourceURLs: [(key: String, url: URL)] {
        var result: [(String, URL)] = [("state", stateURL)]
        for (i, ws) in workspaceURLs.enumerated() {
            let name = ws.lastPathComponent.isEmpty ? "workspace-\(i)" : ws.lastPathComponent
            result.append((name, ws))
        }
        return result
    }
}

// MARK: - 协议

protocol BackupService: Sendable {
    func createManualBackup(request: BackupRequest) throws -> BackupOperationResult
}

// MARK: - 实现

struct LocalBackupService: BackupService, Sendable {
    private let backupsRootURL: URL

    init(backupsRootURL: URL = AppPaths.defaultBackupsRootURL) {
        self.backupsRootURL = backupsRootURL
    }

    func createManualBackup(request: BackupRequest) throws -> BackupOperationResult {
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let startTime = Date()
        try ensureBackupsRoot(fm: fm)

        let archiveId = archiveID(label: request.label)
        let archiveRootURL = backupsRootURL.appendingPathComponent(archiveId, isDirectory: true)
        let payloadURL = archiveRootURL.appendingPathComponent("payload", isDirectory: true)
        let metaURL = archiveRootURL.appendingPathComponent("meta.json")

        let openClawVersion = OpenClawPaths.openClawVersion
        let sourcePaths = request.allSourceURLs.map { $0.url.path }

        do {
            try fm.createDirectory(at: payloadURL, withIntermediateDirectories: true)

            for (key, url) in request.allSourceURLs {
                let subdir: URL
                if key == "state" {
                    subdir = payloadURL.appendingPathComponent("state", isDirectory: true)
                } else {
                    subdir = payloadURL
                        .appendingPathComponent("workspaces", isDirectory: true)
                        .appendingPathComponent(key, isDirectory: true)
                }
                try validateSourceURL(url, fm: fm)
                try fm.createDirectory(at: subdir, withIntermediateDirectories: true)
                try copyDirectoryContents(from: url, to: subdir, fm: fm)
            }

            let metrics = try directoryMetrics(at: payloadURL, fm: fm)
            let meta = BackupMeta(
                archiveId: archiveId,
                sourcePath: request.stateURL.path,
                sourcePaths: sourcePaths,
                createdAt: startTime,
                fileCount: metrics.fileCount,
                sizeBytes: metrics.sizeBytes,
                checksum: nil,
                backupType: .manual,
                openClawVersion: openClawVersion,
                includesSchedulerConfig: false,
                schedulerConfigParsed: false,
                schedulerConfigFiles: [],
                status: .success,
                errorMessage: nil
            )
            try writeMeta(meta, to: metaURL, encoder: encoder)

            return BackupOperationResult(
                meta: meta,
                archiveRootURL: archiveRootURL,
                elapsed: Date().timeIntervalSince(startTime)
            )
        } catch {
            try? fm.createDirectory(at: archiveRootURL, withIntermediateDirectories: true)
            let failedMeta = BackupMeta(
                archiveId: archiveId,
                sourcePath: request.stateURL.path,
                sourcePaths: sourcePaths,
                createdAt: startTime,
                fileCount: 0,
                sizeBytes: 0,
                checksum: nil,
                backupType: .manual,
                openClawVersion: openClawVersion,
                includesSchedulerConfig: false,
                schedulerConfigParsed: false,
                schedulerConfigFiles: [],
                status: .failed,
                errorMessage: error.localizedDescription
            )
            try? writeMeta(failedMeta, to: metaURL, encoder: encoder)
            throw BackClawError.backupFailed(error.localizedDescription)
        }
    }

    // MARK: - 私有方法（全部接受 fm 参数，避免跨线程共享）

    private func ensureBackupsRoot(fm: FileManager) throws {
        do {
            try fm.createDirectory(at: backupsRootURL, withIntermediateDirectories: true)
        } catch {
            throw BackClawError.cannotCreateArchive(error.localizedDescription)
        }
    }

    private func validateSourceURL(_ sourceURL: URL, fm: FileManager) throws {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw BackClawError.invalidSourcePath
        }
    }

    private func copyDirectoryContents(from sourceURL: URL, to destinationURL: URL, fm: FileManager) throws {
        let contents = try fm.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for itemURL in contents {
            let target = destinationURL.appendingPathComponent(itemURL.lastPathComponent)
            try fm.copyItem(at: itemURL, to: target)
        }
    }

    private func directoryMetrics(at directoryURL: URL, fm: FileManager) throws -> (fileCount: Int, sizeBytes: Int64) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return (0, 0) }

        var fileCount = 0
        var sizeBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                fileCount += 1
                sizeBytes += Int64(values.fileSize ?? 0)
            }
        }
        return (fileCount, sizeBytes)
    }

    private func writeMeta(_ meta: BackupMeta, to metaURL: URL, encoder: JSONEncoder) throws {
        let data = try encoder.encode(meta)
        try data.write(to: metaURL, options: .atomic)
    }

    private func archiveID(label: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = formatter.string(from: Date())
        guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }
        return "\(base)-\(sanitize(label: label))"
    }

    private func sanitize(label: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return label.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
    }
}
