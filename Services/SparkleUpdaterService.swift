import Foundation
import Sparkle

@MainActor
final class SparkleUpdaterService: ObservableObject {
    static let shared = SparkleUpdaterService()

    @Published private(set) var isConfigured = false
    @Published private(set) var configurationIssue: String?

    private let updaterController: SPUStandardUpdaterController?

    private init() {
        let configuration = Self.loadConfiguration()
        isConfigured = configuration.isConfigured
        configurationIssue = configuration.issue

        guard configuration.isConfigured else {
            updaterController = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
    }

    @discardableResult
    func checkForUpdates() -> Bool {
        guard let updaterController else { return false }
        updaterController.checkForUpdates(nil)
        return true
    }

    private static func loadConfiguration(bundle: Bundle = .main) -> (isConfigured: Bool, issue: String?) {
        let keys = ["SUFeedURL", "SUPublicEDKey"]
        let missing = keys.filter { key in
            let value = (bundle.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty != false
        }

        if missing.isEmpty {
            return (true, nil)
        }
        return (
            false,
            "Sparkle is not configured. Missing Info.plist key(s): \(missing.joined(separator: ", "))."
        )
    }
}
