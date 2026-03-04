import Foundation

protocol BackupRepository {
    func fetchArchives() throws -> [BackupArchive]
    func deleteArchive(_ archive: BackupArchive) throws
}

struct LocalBackupRepository: BackupRepository {
    private let fileManager: FileManager
    private let backupsRootURL: URL
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        backupsRootURL: URL = AppPaths.defaultBackupsRootURL,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.backupsRootURL = backupsRootURL
        self.decoder = decoder
    }

    func fetchArchives() throws -> [BackupArchive] {
        guard fileManager.fileExists(atPath: backupsRootURL.path) else {
            return []
        }

        let archiveDirs = try fileManager.contentsOfDirectory(
            at: backupsRootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        decoder.dateDecodingStrategy = .iso8601
        var archives: [BackupArchive] = []

        for archiveRootURL in archiveDirs {
            let metaURL = archiveRootURL.appendingPathComponent("meta.json")
            let payloadURL = archiveRootURL.appendingPathComponent("payload", isDirectory: true)

            guard fileManager.fileExists(atPath: metaURL.path) else { continue }
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? decoder.decode(BackupMeta.self, from: data) else { continue }

            archives.append(
                BackupArchive(
                    meta: meta,
                    rootURL: archiveRootURL,
                    payloadURL: payloadURL,
                    metaURL: metaURL
                )
            )
        }

        return archives.sorted { $0.meta.createdAt > $1.meta.createdAt }
    }

    func deleteArchive(_ archive: BackupArchive) throws {
        try fileManager.removeItem(at: archive.rootURL)
    }
}
