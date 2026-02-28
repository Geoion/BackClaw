import SwiftUI
import AppKit

enum AppearanceMode: String, CaseIterable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum AppLanguage: String, CaseIterable, Sendable {
    case system = "system"
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case spanish = "es"
    case italian = "it"
    case russian = "ru"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .russian: return "Русский"
        }
    }

    var effectiveCode: String {
        if self != .system { return rawValue }
        let preferred = Locale.preferredLanguages.first ?? "en"
        let supported = ["zh-Hant", "zh-Hans", "ja", "ko", "de", "es", "it", "ru", "en"]
        return supported.first(where: { preferred.hasPrefix($0) }) ?? "en"
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
            reloadBundle()
        }
    }

    @Published private(set) var bundle: Bundle = .main
    @Published var languageRefreshId = UUID()

    private init() {
        let savedMode = UserDefaults.standard.string(forKey: "appearanceMode")
            .flatMap { AppearanceMode(rawValue: $0) } ?? .system
        let savedLang = UserDefaults.standard.string(forKey: "appLanguage")
            .flatMap { AppLanguage(rawValue: $0) } ?? .system

        self.appearanceMode = savedMode
        self.appLanguage = savedLang

        applyAppearance()
        reloadBundle()
    }

    func applyAppearance() {
        NSApp.appearance = appearanceMode.nsAppearance
    }

    private func reloadBundle() {
        let code = appLanguage.effectiveCode
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
        languageRefreshId = UUID()
    }

    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

@MainActor
func L(_ key: String) -> String {
    AppState.shared.localized(key)
}
