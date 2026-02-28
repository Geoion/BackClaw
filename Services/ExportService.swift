import Foundation

// MARK: - 导出格式

enum ExportFormat: String, CaseIterable, Identifiable {
    case tarGz = "tar.gz"
    case zip   = "zip"

    var id: String { rawValue }
    var displayName: String { rawValue }
    var fileExtension: String { rawValue }

    var systemImage: String {
        switch self {
        case .tarGz: return "archivebox"
        case .zip:   return "doc.zipper"
        }
    }
}

// MARK: - 压缩级别

enum CompressionLevel: String, CaseIterable, Identifiable {
    case fast     = "fast"
    case standard = "standard"
    case best     = "best"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast:     return "快速（体积较大）"
        case .standard: return "标准"
        case .best:     return "高压缩（速度较慢）"
        }
    }

    /// zip Compression framework level (0.0 ~ 1.0)
    var zipLevel: Double {
        switch self {
        case .fast:     return 0.1
        case .standard: return 0.5
        case .best:     return 1.0
        }
    }

    /// tar -z 对应的 gzip level flag（通过环境变量 GZIP 传递）
    var gzipEnvValue: String {
        switch self {
        case .fast:     return "-1"
        case .standard: return "-6"
        case .best:     return "-9"
        }
    }
}

// MARK: - 导出请求

struct ExportRequest: Sendable {
    let archive: BackupArchive
    let format: ExportFormat
    let compressionLevel: CompressionLevel
    let outputDirectory: URL
}

// MARK: - 导出结果

struct ExportResult: Sendable {
    let outputURL: URL
    let sizeBytes: Int64
    let elapsed: TimeInterval
}

// MARK: - 进度回调

typealias ExportProgressHandler = @Sendable (Double) -> Void

// MARK: - 服务

struct ExportService: Sendable {

    func export(
        request: ExportRequest,
        onProgress: ExportProgressHandler? = nil
    ) async throws -> ExportResult {
        let startTime = Date()
        let archiveId = request.archive.meta.archiveId
        let outputURL = request.outputDirectory
            .appendingPathComponent("\(archiveId).\(request.format.fileExtension)")

        // 如果目标文件已存在则删除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        switch request.format {
        case .tarGz:
            try await exportTarGz(
                sourceURL: request.archive.payloadURL,
                outputURL: outputURL,
                level: request.compressionLevel,
                onProgress: onProgress
            )
        case .zip:
            try await exportZip(
                sourceURL: request.archive.payloadURL,
                outputURL: outputURL,
                level: request.compressionLevel,
                onProgress: onProgress
            )
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0

        return ExportResult(
            outputURL: outputURL,
            sizeBytes: size,
            elapsed: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - tar.gz（调用系统 tar，支持压缩级别）

    private func exportTarGz(
        sourceURL: URL,
        outputURL: URL,
        level: CompressionLevel,
        onProgress: ExportProgressHandler?
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            onProgress?(0.05)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            task.arguments = [
                "-czf", outputURL.path,
                "-C", sourceURL.deletingLastPathComponent().path,
                sourceURL.lastPathComponent
            ]
            // 通过 GZIP 环境变量传递压缩级别
            var env = ProcessInfo.processInfo.environment
            env["GZIP"] = level.gzipEnvValue
            task.environment = env

            let errorPipe = Pipe()
            task.standardError = errorPipe

            try task.run()
            onProgress?(0.5)
            task.waitUntilExit()
            onProgress?(1.0)

            guard task.terminationStatus == 0 else {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8) ?? "未知错误"
                throw ExportError.compressionFailed("tar 退出码 \(task.terminationStatus): \(errMsg)")
            }
        }.value
    }

    // MARK: - zip（使用系统 zip 命令，支持压缩级别）

    private func exportZip(
        sourceURL: URL,
        outputURL: URL,
        level: CompressionLevel,
        onProgress: ExportProgressHandler?
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            onProgress?(0.05)

            let levelFlag: String
            switch level {
            case .fast:     levelFlag = "-1"
            case .standard: levelFlag = "-6"
            case .best:     levelFlag = "-9"
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            task.arguments = [
                levelFlag,
                "-r",
                outputURL.path,
                sourceURL.lastPathComponent
            ]
            task.currentDirectoryURL = sourceURL.deletingLastPathComponent()

            let errorPipe = Pipe()
            task.standardError = errorPipe
            task.standardOutput = Pipe()

            try task.run()
            onProgress?(0.5)
            task.waitUntilExit()
            onProgress?(1.0)

            guard task.terminationStatus == 0 else {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8) ?? "未知错误"
                throw ExportError.compressionFailed("zip 退出码 \(task.terminationStatus): \(errMsg)")
            }
        }.value
    }
}

// MARK: - 错误

enum ExportError: LocalizedError {
    case compressionFailed(String)
    case outputDirectoryNotWritable

    var errorDescription: String? {
        switch self {
        case .compressionFailed(let msg): return "压缩失败：\(msg)"
        case .outputDirectoryNotWritable: return "输出目录不可写"
        }
    }
}
