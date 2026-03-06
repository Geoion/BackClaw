import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L("General"), systemImage: "gearshape") }

            StorageSettingsTab()
                .tabItem { Label(L("Storage"), systemImage: "internaldrive") }

            AboutTab()
                .tabItem { Label(L("About"), systemImage: "info.circle") }
        }
        .id(appState.languageRefreshId)
        .frame(width: 480)
        .fixedSize()
    }
}

// MARK: - 通用

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("lastCustomStatePath") private var customStatePath = ""
    @AppStorage("autoRefreshOnLaunch") private var autoRefreshOnLaunch = true

    var body: some View {
        Form {
            Section(L("OpenClaw Path")) {
                LabeledContent(L("State Directory")) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(customStatePath.isEmpty ? OpenClawPaths.stateDirectory.path : customStatePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !customStatePath.isEmpty {
                            Button(L("Reset to Default")) { customStatePath = "" }
                                .font(.caption)
                                .buttonStyle(.link)
                        }
                    }
                }

                LabeledContent(L("Detected Version")) {
                    Text(OpenClawPaths.openClawVersion)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("Behavior")) {
                Toggle(L("Auto-refresh on Launch"), isOn: $autoRefreshOnLaunch)
            }

            Section(L("Appearance")) {
                Picker(L("Appearance"), selection: $appState.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(localizedModeName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L("Language")) {
                Picker(L("Language"), selection: $appState.appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 8)
    }

    private func localizedModeName(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return L("System")
        case .light: return L("Light")
        case .dark: return L("Dark")
        }
    }
}

// MARK: - 存储

private struct StorageSettingsTab: View {
    @State private var backupsSize: String = ""
    @State private var backupsCount: Int = 0

    var body: some View {
        Form {
            Section(L("Backup Storage Location")) {
                LabeledContent(L("Path")) {
                    HStack(spacing: 6) {
                        Text(AppPaths.defaultBackupsRootURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.defaultBackupsRootURL])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                LabeledContent(L("Backup Count")) {
                    Text("\(backupsCount) \(L("archives"))")
                        .foregroundStyle(.secondary)
                }

                LabeledContent(L("Disk Usage")) {
                    Text(backupsSize.isEmpty ? L("Calculating...") : backupsSize)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 8)
        .onAppear { calculateStorage() }
    }

    private func calculateStorage() {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let root = AppPaths.defaultBackupsRootURL
            var totalSize: Int64 = 0
            var count = 0

            if let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                count = dirs.count
                for dir in dirs {
                    guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: []) else { continue }
                    let urls = enumerator.allObjects.compactMap { $0 as? URL }
                    for fileURL in urls {
                        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalSize += Int64(size)
                        }
                    }
                }
            }

            let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            await MainActor.run {
                backupsSize = sizeStr
                backupsCount = count
            }
        }
    }
}

// MARK: - 关于

private struct AboutTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCheckingForUpdates = false
    @State private var showUpToDateAlert = false

    private var appVersion: String { AppPaths.appVersion }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 4) {
                Text("BackClaw")
                    .font(.title2).bold()
                Text("\(L("Version")) \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(L("OpenClaw Backup & Restore Tool"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text(L("Author"))
                        .foregroundStyle(.secondary)
                    Text("Geoion")
                }
                GridRow {
                    Text(L("GitHub"))
                        .foregroundStyle(.secondary)
                    Button {
                        if let url = URL(string: "https://github.com/Geoion/BackClaw") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("github.com/Geoion/BackClaw")
                            .font(.system(.body, design: .monospaced))
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.subheadline)

            Button(isCheckingForUpdates ? L("Checking...") : L("Check for Updates")) {
                guard !isCheckingForUpdates else { return }
                isCheckingForUpdates = true
                Task {
                    let hasUpdate = await appState.checkForUpdates()
                    isCheckingForUpdates = false
                    if !hasUpdate {
                        showUpToDateAlert = true
                    }
                }
            }
            .disabled(isCheckingForUpdates)
            .alert(L("Already Up to Date"), isPresented: $showUpToDateAlert) {
                Button(L("OK"), role: .cancel) {}
            } message: {
                Text(L("BackClaw is up to date."))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
