import Foundation

enum BackupType: String, Codable {
    case manual
    case scheduled
    case preRestoreSnapshot = "pre-restore-snapshot"
}
