import Foundation

// MARK: - 备份请求

enum BackupSourceKind: String, Sendable {
    case state
    case workspace
}

enum BackupEssentials {
    static let workspaceRequiredRootFiles: Set<String> = [
        "agents.md", "soul.md", "user.md", "identity.md", "tools.md", "heartbeat.md", "memory.md", "boot.md", "bootstrap.md"
    ]

    static let workspaceRequiredRootDirectories: Set<String> = [
        "memory", "skills", "cron"
    ]

    static let stateRequiredRootFiles: Set<String> = [
        "openclaw.json", "openclaw.json5", "openclaw.yaml", "openclaw.yml", "openclaw.toml",
        "config.json", "config.json5", "config.yaml", "config.yml", "config.toml"
    ]

    static let stateRequiredRootDirectories: Set<String> = [
        "cron"
    ]

    static func requiredDisplayItems(for sourceKind: BackupSourceKind) -> [String] {
        switch sourceKind {
        case .workspace:
            return [
                "workspace/ (full)"
            ]
        case .state:
            return [
                "openclaw.json/openclaw.json5", "cron/", "workspace*/ (full)"
            ]
        }
    }

    static func optionalTopLevelDirectoryNames(
        in sourceURL: URL,
        sourceKind: BackupSourceKind,
        fm: FileManager = .default
    ) -> [String] {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }
        if sourceKind == .workspace {
            return []
        }

        let urls = (try? fm.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            let normalized = url.lastPathComponent.lowercased()
            if isRequiredTopLevelDirectory(named: normalized, sourceKind: sourceKind) {
                return nil
            }
            if sourceKind == .state, isWorkspaceContainerName(normalized) {
                // Workspace directories are fully included in partial mode.
                return nil
            }
            return url.lastPathComponent
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func shouldIncludeFile(
        relativePathComponents components: [String],
        sourceKind: BackupSourceKind,
        selectedTopLevelNames: Set<String>
    ) -> Bool {
        guard let topLevel = components.first else { return false }
        if selectedTopLevelNames.contains(topLevel) { return true }

        switch sourceKind {
        case .workspace:
            // In partial mode, explicit workspace sources are fully required.
            return true

        case .state:
            if components.count == 1 && stateRequiredRootFiles.contains(topLevel) {
                return true
            }
            if stateRequiredRootDirectories.contains(topLevel) {
                return true
            }

            // In partial mode, workspace/workspace-* under state are fully required.
            guard isWorkspaceContainerName(topLevel) else { return false }
            return components.count >= 2
        }
    }

    static func shouldIncludeDirectory(
        relativePathComponents components: [String],
        sourceKind: BackupSourceKind,
        selectedTopLevelNames: Set<String>
    ) -> Bool {
        guard let topLevel = components.first else { return false }
        if selectedTopLevelNames.contains(topLevel) { return true }

        switch sourceKind {
        case .workspace:
            return true

        case .state:
            if stateRequiredRootDirectories.contains(topLevel) {
                return true
            }

            guard isWorkspaceContainerName(topLevel) else { return false }
            return true
        }
    }

    static func shouldTraverseDirectory(
        relativePathComponents components: [String],
        sourceKind: BackupSourceKind,
        selectedTopLevelNames: Set<String>
    ) -> Bool {
        guard let topLevel = components.first else { return false }
        if selectedTopLevelNames.contains(topLevel) { return true }

        switch sourceKind {
        case .workspace:
            return true

        case .state:
            if components.count == 1 {
                return stateRequiredRootDirectories.contains(topLevel) || isWorkspaceContainerName(topLevel)
            }

            if stateRequiredRootDirectories.contains(topLevel) {
                return true
            }

            return isWorkspaceContainerName(topLevel)
        }
    }

    private static func isRequiredTopLevelDirectory(named name: String, sourceKind: BackupSourceKind) -> Bool {
        switch sourceKind {
        case .workspace:
            return workspaceRequiredRootDirectories.contains(name)
        case .state:
            return stateRequiredRootDirectories.contains(name)
        }
    }

    private static func isWorkspaceContainerName(_ name: String) -> Bool {
        name == "workspace" || name.hasPrefix("workspace-")
    }
}

enum BackupContentMode: String, CaseIterable, Sendable {
    case all
    case essentials
}

struct BackupRequest: Sendable {
    let stateURL: URL
    let workspaceURLs: [URL]
    let assistantProduct: BackupAssistantProduct
    let contentMode: BackupContentMode
    let optionalTopLevelSelectionsBySourcePath: [String: Set<String>]
    let label: String?

    var allSourceURLs: [(key: String, url: URL, kind: BackupSourceKind)] {
        var usedKeys: Set<String> = ["state"]
        var result: [(String, URL, BackupSourceKind)] = [("state", stateURL, .state)]

        for (index, workspaceURL) in workspaceURLs.enumerated() {
            let base = workspaceURL.lastPathComponent.isEmpty ? "workspace-\(index + 1)" : workspaceURL.lastPathComponent

            var uniqueKey = base
            var suffix = 2
            while usedKeys.contains(uniqueKey) {
                uniqueKey = "\(base)-\(suffix)"
                suffix += 1
            }

            usedKeys.insert(uniqueKey)
            result.append((uniqueKey, workspaceURL, .workspace))
        }

        return result
    }
}

// MARK: - 协议

protocol BackupService: Sendable {
    func createManualBackup(request: BackupRequest) throws -> BackupOperationResult
}

struct BackupEstimate: Equatable, Sendable {
    let fileCount: Int
    let sizeBytes: Int64
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

            for source in request.allSourceURLs {
                let subdir: URL
                if source.kind == .state {
                    subdir = payloadURL.appendingPathComponent("state", isDirectory: true)
                } else {
                    subdir = payloadURL
                        .appendingPathComponent("workspaces", isDirectory: true)
                        .appendingPathComponent(source.key, isDirectory: true)
                }

                try validateSourceURL(source.url, fm: fm)
                try fm.createDirectory(at: subdir, withIntermediateDirectories: true)

                switch request.contentMode {
                case .all:
                    try copyDirectoryContents(from: source.url, to: subdir, fm: fm)
                case .essentials:
                    let sourcePathKey = source.url.standardizedFileURL.path
                    let selectedTopLevels = request.optionalTopLevelSelectionsBySourcePath[sourcePathKey] ?? []
                    try copyEssentialContents(
                        from: source.url,
                        to: subdir,
                        sourceKind: source.kind,
                        extraTopLevelNames: selectedTopLevels,
                        fm: fm
                    )
                }
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
                assistantProduct: request.assistantProduct,
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
                assistantProduct: request.assistantProduct,
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

    func estimateBackupMetrics(request: BackupRequest) throws -> BackupEstimate {
        let fm = FileManager.default
        var totalCount = 0
        var totalSize: Int64 = 0

        for source in request.allSourceURLs {
            try validateSourceURL(source.url, fm: fm)

            switch request.contentMode {
            case .all:
                let metrics = try directoryMetrics(at: source.url, fm: fm)
                totalCount += metrics.fileCount
                totalSize += metrics.sizeBytes
            case .essentials:
                let sourcePathKey = source.url.standardizedFileURL.path
                let selectedTopLevels = request.optionalTopLevelSelectionsBySourcePath[sourcePathKey] ?? []
                let metrics = try estimateEssentialMetrics(
                    at: source.url,
                    sourceKind: source.kind,
                    extraTopLevelNames: selectedTopLevels,
                    fm: fm
                )
                totalCount += metrics.fileCount
                totalSize += metrics.sizeBytes
            }
        }

        return BackupEstimate(fileCount: totalCount, sizeBytes: totalSize)
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

    private func copyEssentialContents(
        from sourceURL: URL,
        to destinationURL: URL,
        sourceKind: BackupSourceKind,
        extraTopLevelNames: Set<String>,
        fm: FileManager
    ) throws {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let normalizedExtraTopLevelNames = Set(extraTopLevelNames.map { $0.lowercased() })

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else { return }

        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: keys)
            let prefix = sourceURL.path.hasSuffix("/") ? sourceURL.path : sourceURL.path + "/"
            guard itemURL.path.hasPrefix(prefix) else { continue }
            let relativePath = String(itemURL.path.dropFirst(prefix.count))
            let components = relativePath.split(separator: "/").map { $0.lowercased() }
            guard !components.isEmpty else { continue }

            if values.isDirectory == true {
                let shouldIncludeDirectory = BackupEssentials.shouldIncludeDirectory(
                    relativePathComponents: components,
                    sourceKind: sourceKind,
                    selectedTopLevelNames: normalizedExtraTopLevelNames
                )
                if shouldIncludeDirectory {
                    let targetDir = destinationURL.appendingPathComponent(relativePath, isDirectory: true)
                    try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                }

                let shouldTraverse = BackupEssentials.shouldTraverseDirectory(
                    relativePathComponents: components,
                    sourceKind: sourceKind,
                    selectedTopLevelNames: normalizedExtraTopLevelNames
                )
                if !shouldTraverse {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true else { continue }

            let includeFile = BackupEssentials.shouldIncludeFile(
                relativePathComponents: components,
                sourceKind: sourceKind,
                selectedTopLevelNames: normalizedExtraTopLevelNames
            )
            guard includeFile else { continue }

            let targetURL = destinationURL.appendingPathComponent(relativePath)
            try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: targetURL.path) {
                try fm.removeItem(at: targetURL)
            }
            try fm.copyItem(at: itemURL, to: targetURL)
        }
    }

    private func estimateEssentialMetrics(
        at sourceURL: URL,
        sourceKind: BackupSourceKind,
        extraTopLevelNames: Set<String>,
        fm: FileManager
    ) throws -> (fileCount: Int, sizeBytes: Int64) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let normalizedExtraTopLevelNames = Set(extraTopLevelNames.map { $0.lowercased() })

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else { return (0, 0) }

        var fileCount = 0
        var sizeBytes: Int64 = 0

        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: keys)
            let prefix = sourceURL.path.hasSuffix("/") ? sourceURL.path : sourceURL.path + "/"
            guard itemURL.path.hasPrefix(prefix) else { continue }
            let relativePath = String(itemURL.path.dropFirst(prefix.count))
            let components = relativePath.split(separator: "/").map { $0.lowercased() }
            guard !components.isEmpty else { continue }

            if values.isDirectory == true {
                let shouldTraverse = BackupEssentials.shouldTraverseDirectory(
                    relativePathComponents: components,
                    sourceKind: sourceKind,
                    selectedTopLevelNames: normalizedExtraTopLevelNames
                )
                if !shouldTraverse {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true else { continue }
            let includeFile = BackupEssentials.shouldIncludeFile(
                relativePathComponents: components,
                sourceKind: sourceKind,
                selectedTopLevelNames: normalizedExtraTopLevelNames
            )
            guard includeFile else { continue }

            fileCount += 1
            sizeBytes += Int64(values.fileSize ?? 0)
        }

        return (fileCount, sizeBytes)
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
