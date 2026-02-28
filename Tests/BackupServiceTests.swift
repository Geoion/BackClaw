import Foundation
import Testing
@testable import BackClaw

struct BackupServiceTests {

    @Test
    func createManualBackupWritesMetaAndPayload() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)
        let backupsURL = tempRoot.appendingPathComponent("backups", isDirectory: true)

        try fm.createDirectory(at: stateURL, withIntermediateDirectories: true)
        let payload = try #require("hello".data(using: .utf8))
        try payload.write(to: stateURL.appendingPathComponent("hello.txt"))

        let service = LocalBackupService(backupsRootURL: backupsURL)
        let request = BackupRequest(stateURL: stateURL, workspaceURLs: [], label: "test")
        let result = try service.createManualBackup(request: request)

        #expect(result.meta.status == .success)
        #expect(result.meta.fileCount == 1)
        #expect(fm.fileExists(atPath: result.archiveRootURL.appendingPathComponent("meta.json").path))
        #expect(fm.fileExists(atPath: result.archiveRootURL.appendingPathComponent("payload/state/hello.txt").path))
    }

    @Test
    func repositoryReadsArchivesOrderedByDate() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backupsURL = tempRoot.appendingPathComponent("backups", isDirectory: true)
        try fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let aDate = Date(timeIntervalSince1970: 100)
        let bDate = Date(timeIntervalSince1970: 200)

        try createArchive(id: "A", date: aDate, backupsURL: backupsURL, encoder: encoder)
        try createArchive(id: "B", date: bDate, backupsURL: backupsURL, encoder: encoder)

        let repository = LocalBackupRepository(backupsRootURL: backupsURL)
        let archives = try repository.fetchArchives()

        #expect(archives.count == 2)
        #expect(archives.first?.meta.archiveId == "B")
    }

    private func createArchive(
        id: String,
        date: Date,
        backupsURL: URL,
        encoder: JSONEncoder
    ) throws {
        let fm = FileManager.default
        let archiveURL = backupsURL.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        let payloadURL = archiveURL.appendingPathComponent("payload", isDirectory: true)
        try fm.createDirectory(at: payloadURL, withIntermediateDirectories: true)

        let meta = BackupMeta(
            archiveId: id,
            sourcePath: "/tmp/source",
            sourcePaths: ["/tmp/source"],
            createdAt: date,
            fileCount: 0,
            sizeBytes: 0,
            checksum: nil,
            backupType: .manual,
            openClawVersion: "unknown",
            includesSchedulerConfig: false,
            schedulerConfigParsed: false,
            schedulerConfigFiles: [],
            status: .success,
            errorMessage: nil
        )
        let data = try encoder.encode(meta)
        try data.write(to: archiveURL.appendingPathComponent("meta.json"))
    }
}
