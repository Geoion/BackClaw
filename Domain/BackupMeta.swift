import Foundation

struct BackupMeta: Codable, Identifiable {
    let archiveId: String
    let sourcePath: String
    let sourcePaths: [String]
    let createdAt: Date
    let fileCount: Int
    let sizeBytes: Int64
    let checksum: String?
    let backupType: BackupType
    /// 备份时记录的 OpenClaw 版本号，读取失败时为 "unknown"
    let openClawVersion: String
    let includesSchedulerConfig: Bool
    let schedulerConfigParsed: Bool
    let schedulerConfigFiles: [String]
    let status: BackupStatus
    let errorMessage: String?

    var id: String { archiveId }

    // MARK: - 兼容旧格式的自定义解码

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        archiveId             = try c.decode(String.self, forKey: .archiveId)
        sourcePath            = (try? c.decode(String.self, forKey: .sourcePath)) ?? ""
        sourcePaths           = (try? c.decode([String].self, forKey: .sourcePaths)) ?? []
        createdAt             = try c.decode(Date.self, forKey: .createdAt)
        fileCount             = (try? c.decode(Int.self, forKey: .fileCount)) ?? 0
        sizeBytes             = (try? c.decode(Int64.self, forKey: .sizeBytes)) ?? 0
        checksum              = try? c.decode(String.self, forKey: .checksum)
        backupType            = (try? c.decode(BackupType.self, forKey: .backupType)) ?? .manual
        openClawVersion       = (try? c.decode(String.self, forKey: .openClawVersion)) ?? "unknown"
        includesSchedulerConfig = (try? c.decode(Bool.self, forKey: .includesSchedulerConfig)) ?? false
        schedulerConfigParsed   = (try? c.decode(Bool.self, forKey: .schedulerConfigParsed)) ?? false
        schedulerConfigFiles    = (try? c.decode([String].self, forKey: .schedulerConfigFiles)) ?? []
        status                = (try? c.decode(BackupStatus.self, forKey: .status)) ?? .success
        errorMessage          = try? c.decode(String.self, forKey: .errorMessage)
    }

    // MARK: - 正常初始化

    init(
        archiveId: String,
        sourcePath: String,
        sourcePaths: [String],
        createdAt: Date,
        fileCount: Int,
        sizeBytes: Int64,
        checksum: String?,
        backupType: BackupType,
        openClawVersion: String,
        includesSchedulerConfig: Bool,
        schedulerConfigParsed: Bool,
        schedulerConfigFiles: [String],
        status: BackupStatus,
        errorMessage: String?
    ) {
        self.archiveId = archiveId
        self.sourcePath = sourcePath
        self.sourcePaths = sourcePaths
        self.createdAt = createdAt
        self.fileCount = fileCount
        self.sizeBytes = sizeBytes
        self.checksum = checksum
        self.backupType = backupType
        self.openClawVersion = openClawVersion
        self.includesSchedulerConfig = includesSchedulerConfig
        self.schedulerConfigParsed = schedulerConfigParsed
        self.schedulerConfigFiles = schedulerConfigFiles
        self.status = status
        self.errorMessage = errorMessage
    }
}

enum BackupStatus: String, Codable {
    case success
    case failed
}

// MARK: - 版本兼容性

enum VersionCompatibility {
    case same
    case downgrade(current: String, backup: String)
    case upgrade(current: String, backup: String)
    case unknown(current: String, backup: String)

    var requiresStrongWarning: Bool {
        if case .downgrade = self { return true }
        return false
    }

    var warningMessage: String? {
        switch self {
        case .same:
            return nil
        case .downgrade(let current, let backup):
            return String(format: NSLocalizedString("Version Warning Downgrade", comment: ""), current, backup)
        case .upgrade(let current, let backup):
            return String(format: NSLocalizedString("Version Warning Upgrade", comment: ""), current, backup)
        case .unknown(let current, let backup):
            return String(format: NSLocalizedString("Version Warning Unknown", comment: ""), current, backup)
        }
    }
}

extension BackupMeta {
    func versionCompatibility() -> VersionCompatibility {
        let current = OpenClawPaths.openClawVersion
        let backup = openClawVersion

        if current == "unknown" || backup == "unknown" {
            return .unknown(current: current, backup: backup)
        }

        let currentNorm = current.hasPrefix("v") ? String(current.dropFirst()) : current
        let backupNorm  = backup.hasPrefix("v")  ? String(backup.dropFirst())  : backup

        switch compareVersions(currentNorm, backupNorm) {
        case .orderedSame:       return .same
        case .orderedDescending: return .downgrade(current: current, backup: backup)
        case .orderedAscending:  return .upgrade(current: current, backup: backup)
        }
    }

    private func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(aParts.count, bParts.count)
        for i in 0..<maxLen {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av > bv ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }
}
