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
        let request = BackupRequest(
            stateURL: stateURL,
            workspaceURLs: [],
            assistantProduct: .openclaw,
            contentMode: .all,
            optionalTopLevelSelectionsBySourcePath: [:],
            label: "test"
        )
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

    @Test
    func createManualBackupEssentialsIncludesRequiredAndSelectedOptionalForState() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)
        let backupsURL = tempRoot.appendingPathComponent("backups", isDirectory: true)

        try fm.createDirectory(at: stateURL, withIntermediateDirectories: true)
        let configData = try #require("config".data(using: .utf8))
        try configData.write(to: stateURL.appendingPathComponent("openclaw.json"))

        let cronURL = stateURL.appendingPathComponent("cron", isDirectory: true)
        try fm.createDirectory(at: cronURL, withIntermediateDirectories: true)
        let jobData = try #require("job".data(using: .utf8))
        try jobData.write(to: cronURL.appendingPathComponent("jobs.json"))

        let workspaceURL = stateURL.appendingPathComponent("workspace", isDirectory: true)
        try fm.createDirectory(at: workspaceURL.appendingPathComponent("memory", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: workspaceURL.appendingPathComponent("skills", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: workspaceURL.appendingPathComponent("notes", isDirectory: true), withIntermediateDirectories: true)
        let agentData = try #require("agent".data(using: .utf8))
        let memoryData = try #require("memory".data(using: .utf8))
        let skillData = try #require("skill".data(using: .utf8))
        let notesData = try #require("notes".data(using: .utf8))
        try agentData.write(to: workspaceURL.appendingPathComponent("AGENTS.md"))
        try memoryData.write(to: workspaceURL.appendingPathComponent("memory/main.md"))
        try skillData.write(to: workspaceURL.appendingPathComponent("skills/tool.md"))
        try notesData.write(to: workspaceURL.appendingPathComponent("notes/ignore.md"))

        let logsURL = stateURL.appendingPathComponent("logs", isDirectory: true)
        try fm.createDirectory(at: logsURL, withIntermediateDirectories: true)
        let logData = try #require("log".data(using: .utf8))
        try logData.write(to: logsURL.appendingPathComponent("latest.log"))

        let miscURL = stateURL.appendingPathComponent("misc", isDirectory: true)
        try fm.createDirectory(at: miscURL, withIntermediateDirectories: true)
        let miscData = try #require("misc".data(using: .utf8))
        try miscData.write(to: miscURL.appendingPathComponent("skip.txt"))

        let service = LocalBackupService(backupsRootURL: backupsURL)
        let request = BackupRequest(
            stateURL: stateURL,
            workspaceURLs: [],
            assistantProduct: .openclaw,
            contentMode: .essentials,
            optionalTopLevelSelectionsBySourcePath: [
                stateURL.standardizedFileURL.path: Set(["logs"])
            ],
            label: "essentials-state"
        )
        let result = try service.createManualBackup(request: request)
        let payload = result.archiveRootURL.appendingPathComponent("payload/state", isDirectory: true)

        #expect(fm.fileExists(atPath: payload.appendingPathComponent("openclaw.json").path))
        #expect(fm.fileExists(atPath: payload.appendingPathComponent("cron/jobs.json").path))
        #expect(fm.fileExists(atPath: payload.appendingPathComponent("workspace/AGENTS.md").path))
        #expect(fm.fileExists(atPath: payload.appendingPathComponent("workspace/memory/main.md").path))
        #expect(fm.fileExists(atPath: payload.appendingPathComponent("workspace/skills/tool.md").path))
        #expect(fm.fileExists(atPath: payload.appendingPathComponent("logs/latest.log").path))
        #expect(!fm.fileExists(atPath: payload.appendingPathComponent("workspace/notes/ignore.md").path))
        #expect(!fm.fileExists(atPath: payload.appendingPathComponent("misc/skip.txt").path))
    }

    @Test
    func createManualBackupEssentialsIncludesRequiredAndSelectedOptionalForWorkspaceSource() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)
        let externalWorkspaceURL = tempRoot.appendingPathComponent("agent-main", isDirectory: true)
        let backupsURL = tempRoot.appendingPathComponent("backups", isDirectory: true)

        try fm.createDirectory(at: stateURL, withIntermediateDirectories: true)
        let configData = try #require("config".data(using: .utf8))
        try configData.write(to: stateURL.appendingPathComponent("openclaw.json"))

        try fm.createDirectory(at: externalWorkspaceURL.appendingPathComponent("memory", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: externalWorkspaceURL.appendingPathComponent("skills", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: externalWorkspaceURL.appendingPathComponent("cache", isDirectory: true), withIntermediateDirectories: true)
        let agentData = try #require("agent".data(using: .utf8))
        let memoryData = try #require("memory".data(using: .utf8))
        let skillData = try #require("skill".data(using: .utf8))
        let cacheData = try #require("cache".data(using: .utf8))
        try agentData.write(to: externalWorkspaceURL.appendingPathComponent("AGENTS.md"))
        try memoryData.write(to: externalWorkspaceURL.appendingPathComponent("memory/main.md"))
        try skillData.write(to: externalWorkspaceURL.appendingPathComponent("skills/tool.md"))
        try cacheData.write(to: externalWorkspaceURL.appendingPathComponent("cache/data.bin"))

        let service = LocalBackupService(backupsRootURL: backupsURL)
        let request = BackupRequest(
            stateURL: stateURL,
            workspaceURLs: [externalWorkspaceURL],
            assistantProduct: .openclaw,
            contentMode: .essentials,
            optionalTopLevelSelectionsBySourcePath: [
                externalWorkspaceURL.standardizedFileURL.path: Set(["cache"])
            ],
            label: "essentials-workspace"
        )
        let result = try service.createManualBackup(request: request)
        let workspacesRoot = result.archiveRootURL.appendingPathComponent("payload/workspaces", isDirectory: true)
        let workspaceFolders = try fm.contentsOfDirectory(at: workspacesRoot, includingPropertiesForKeys: nil)
        let backedWorkspace = try #require(workspaceFolders.first)

        #expect(fm.fileExists(atPath: backedWorkspace.appendingPathComponent("AGENTS.md").path))
        #expect(fm.fileExists(atPath: backedWorkspace.appendingPathComponent("memory/main.md").path))
        #expect(fm.fileExists(atPath: backedWorkspace.appendingPathComponent("skills/tool.md").path))
        #expect(fm.fileExists(atPath: backedWorkspace.appendingPathComponent("cache/data.bin").path))
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
            assistantProduct: .openclaw,
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

struct UpdateServiceTests {

    private let sampleChangelog = """
    # Changelog

    ## v1.1.0 — 2026-03-04

    **New**
    - Feature A
    - Feature B

    **Improved**
    - Improvement C

    ## v1.0 — 2026-02-01

    - Initial release
    - Manual backup and restore
    """

    @Test
    func extractSectionReturnsBodyForMatchingTag() {
        let service = UpdateService.shared
        let result = service.extractSection(from: sampleChangelog, tagName: "v1.1.0")
        #expect(result?.contains("Feature A") == true)
        #expect(result?.contains("Improvement C") == true)
        // Should not bleed into the next version
        #expect(result?.contains("Initial release") == false)
    }

    @Test
    func extractSectionNormalizesTagWithoutVPrefix() {
        let service = UpdateService.shared
        let result = service.extractSection(from: sampleChangelog, tagName: "1.0")
        #expect(result?.contains("Initial release") == true)
    }

    @Test
    func extractSectionReturnsNilForUnknownTag() {
        let service = UpdateService.shared
        let result = service.extractSection(from: sampleChangelog, tagName: "v9.9.9")
        #expect(result == nil)
    }

    @Test
    func extractSectionTrimsLeadingAndTrailingBlankLines() {
        let service = UpdateService.shared
        let result = service.extractSection(from: sampleChangelog, tagName: "v1.1.0")
        #expect(result?.hasPrefix("\n") == false)
        #expect(result?.hasSuffix("\n") == false)
    }
}
