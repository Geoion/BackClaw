import Foundation

enum AppPaths {
    static var defaultBackupsRootURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return applicationSupport
            .appendingPathComponent("BackClaw", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }
}
