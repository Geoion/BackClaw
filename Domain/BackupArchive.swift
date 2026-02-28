import Foundation

struct BackupArchive: Identifiable, Equatable {
    static func == (lhs: BackupArchive, rhs: BackupArchive) -> Bool {
        lhs.meta.archiveId == rhs.meta.archiveId
    }
    let meta: BackupMeta
    let rootURL: URL
    let payloadURL: URL
    let metaURL: URL

    var id: String { meta.archiveId }
}
