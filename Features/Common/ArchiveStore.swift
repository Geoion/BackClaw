import Foundation

@MainActor
final class ArchiveStore: ObservableObject {
    @Published private(set) var archives: [BackupArchive] = []
    @Published var latestError: String?

    private let repository: BackupRepository

    init(repository: BackupRepository = LocalBackupRepository()) {
        self.repository = repository
    }

    func refresh() {
        do {
            archives = try repository.fetchArchives()
        } catch {
            latestError = error.localizedDescription
        }
    }

    func prepend(_ archive: BackupArchive) {
        archives.insert(archive, at: 0)
    }
}
