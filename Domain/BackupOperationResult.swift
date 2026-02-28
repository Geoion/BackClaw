import Foundation

struct BackupOperationResult {
    let meta: BackupMeta
    let archiveRootURL: URL
    let elapsed: TimeInterval
}
