import Foundation

struct ImportResult {
    let archive: BackupArchive
    let elapsed: TimeInterval
}

struct ImportService: Sendable {

    private let backupsRootURL: URL

    init(backupsRootURL: URL = AppPaths.defaultBackupsRootURL) {
        self.backupsRootURL = backupsRootURL
    }

    /// 从压缩包（tar.gz / zip）导入为新备份存档
    func importArchive(from fileURL: URL) async throws -> ImportResult {
        let startTime = Date()
        let fm = FileManager.default

        try fm.createDirectory(at: backupsRootURL, withIntermediateDirectories: true)

        // 生成临时解压目录
        let tempDir = backupsRootURL
            .appendingPathComponent(".import-tmp-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 解压
        let ext = fileURL.pathExtension.lowercased()
        if ext == "gz" || fileURL.lastPathComponent.hasSuffix(".tar.gz") {
            try await decompressTarGz(from: fileURL, to: tempDir)
        } else if ext == "zip" {
            try await decompressZip(from: fileURL, to: tempDir)
        } else {
            throw ImportError.unsupportedFormat(ext)
        }

        // 查找解压后的 meta.json
        let metaURL = findMetaJSON(in: tempDir)
        let payloadURL = findPayload(in: tempDir)

        guard let metaURL else {
            throw ImportError.missingMeta
        }

        // 解码 meta
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: metaURL)
        var meta = try decoder.decode(BackupMeta.self, from: data)

        // 如果 archiveId 已存在，加后缀避免冲突
        let archiveId = resolveArchiveId(meta.archiveId)
        if archiveId != meta.archiveId {
            meta = BackupMeta(
                archiveId: archiveId,
                sourcePath: meta.sourcePath,
                sourcePaths: meta.sourcePaths,
                createdAt: meta.createdAt,
                fileCount: meta.fileCount,
                sizeBytes: meta.sizeBytes,
                checksum: meta.checksum,
                backupType: meta.backupType,
                openClawVersion: meta.openClawVersion,
                includesSchedulerConfig: meta.includesSchedulerConfig,
                schedulerConfigParsed: meta.schedulerConfigParsed,
                schedulerConfigFiles: meta.schedulerConfigFiles,
                status: meta.status,
                errorMessage: meta.errorMessage
            )
        }

        // 移动到正式存档目录
        let archiveRootURL = backupsRootURL.appendingPathComponent(archiveId, isDirectory: true)
        try fm.createDirectory(at: archiveRootURL, withIntermediateDirectories: true)

        // 移动 payload
        let destPayloadURL = archiveRootURL.appendingPathComponent("payload", isDirectory: true)
        if let payloadURL {
            try fm.moveItem(at: payloadURL, to: destPayloadURL)
        } else {
            // 没有 payload 子目录，把整个解压内容作为 payload
            try fm.moveItem(at: tempDir, to: destPayloadURL)
        }

        // 写入（可能更新了 archiveId 的）meta.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let metaData = try encoder.encode(meta)
        try metaData.write(to: archiveRootURL.appendingPathComponent("meta.json"), options: .atomic)

        let archive = BackupArchive(
            meta: meta,
            rootURL: archiveRootURL,
            payloadURL: destPayloadURL,
            metaURL: archiveRootURL.appendingPathComponent("meta.json")
        )

        return ImportResult(archive: archive, elapsed: Date().timeIntervalSince(startTime))
    }

    // MARK: - 解压

    private func decompressTarGz(from fileURL: URL, to destURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            task.arguments = ["-xzf", fileURL.path, "-C", destURL.path]
            let errPipe = Pipe()
            task.standardError = errPipe
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw ImportError.decompressionFailed("tar: \(msg)")
            }
        }.value
    }

    private func decompressZip(from fileURL: URL, to destURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            task.arguments = ["-o", fileURL.path, "-d", destURL.path]
            let errPipe = Pipe()
            task.standardError = errPipe
            task.standardOutput = Pipe()
            try task.run()
            task.waitUntilExit()
            // unzip 返回 1 表示有警告但成功，只有 >1 才是真正失败
            guard task.terminationStatus <= 1 else {
                let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw ImportError.decompressionFailed("unzip: \(msg)")
            }
        }.value
    }

    // MARK: - 工具

    private func findMetaJSON(in dir: URL) -> URL? {
        let fm = FileManager.default
        // 直接在根目录
        let direct = dir.appendingPathComponent("meta.json")
        if fm.fileExists(atPath: direct.path) { return direct }
        // 在一级子目录（tar 解压后可能有一层目录）
        if let subs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for sub in subs {
                let candidate = sub.appendingPathComponent("meta.json")
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private func findPayload(in dir: URL) -> URL? {
        let fm = FileManager.default
        let direct = dir.appendingPathComponent("payload")
        if fm.fileExists(atPath: direct.path) { return direct }
        if let subs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for sub in subs {
                let candidate = sub.appendingPathComponent("payload")
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private func resolveArchiveId(_ id: String) -> String {
        let fm = FileManager.default
        var candidate = id
        var suffix = 1
        while fm.fileExists(atPath: backupsRootURL.appendingPathComponent(candidate).path) {
            candidate = "\(id)-imported-\(suffix)"
            suffix += 1
        }
        return candidate
    }
}

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case missingMeta
    case decompressionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "不支持的文件格式：.\(ext)，仅支持 .tar.gz 和 .zip"
        case .missingMeta: return "压缩包内未找到 meta.json，可能不是有效的 BackClaw 备份文件"
        case .decompressionFailed(let msg): return "解压失败：\(msg)"
        }
    }
}
