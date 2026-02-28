import AppKit
import SwiftUI

struct BackupSheetView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @Binding var isPresented: Bool

    @State private var useCustomState = false
    @State private var customStatePath: String = UserDefaults.standard.string(forKey: "lastCustomStatePath") ?? ""
    @State private var workspacePaths: [WorkspacePath] = []
    @State private var addingPath: String = ""
    @State private var customLabel: String = ""
    @State private var phase: BackupPhase = .idle

    private var stateURL: URL {
        if useCustomState, !customStatePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: customStatePath, isDirectory: true)
        }
        return OpenClawPaths.stateDirectory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(L("Backup Now Title"))
                .font(.title2).bold()
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()

            VStack(alignment: .leading, spacing: 18) {

                SectionBlock(
                    title: L("State Directory"),
                    footnote: L("Contains configs, credentials, sessions and all agent data.")
                ) {
                    if !useCustomState {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                            Text(OpenClawPaths.stateDirectory.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(L("Customize")) { useCustomState = true }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        HStack(spacing: 6) {
                            TextField(L("State Directory Path"), text: $customStatePath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .disabled(phase == .running)
                            Button(L("Choose...")) { chooseDirectory(for: .state) }
                                .disabled(phase == .running)
                            Button(L("Reset")) {
                                useCustomState = false
                                customStatePath = ""
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                SectionBlock(
                    title: L("Workspace Directory"),
                    footnote: L("Contains memory and skill files. Each agent has its own workspace in multi-agent setups.")
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(workspacePaths) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                                Text(item.url.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    workspacePaths.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(phase == .running)
                            }
                        }

                        HStack(spacing: 6) {
                            TextField(L("Add Workspace Path..."), text: $addingPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .disabled(phase == .running)
                            Button(L("Browse...")) { chooseDirectory(for: .workspace) }
                                .disabled(phase == .running)
                            Button(L("Add")) { commitAddingPath() }
                                .disabled(addingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .running)
                        }
                    }
                }

                SectionBlock(
                    title: L("Backup Label (Optional)"),
                    footnote: L("Appended to archive ID. Letters, numbers, hyphens only.")
                ) {
                    TextField(L("e.g. upgrade-before-v2"), text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .disabled(phase == .running)
                }

                if phase != .idle {
                    phaseView
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()
                Button(L("Cancel")) { isPresented = false }
                    .disabled(phase == .running)
                    .keyboardShortcut(.escape, modifiers: [])

                Button {
                    runBackup()
                } label: {
                    if phase == .running {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L("Backing Up..."))
                        }
                    } else {
                        Text(L("Start Backup"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(phase == .running)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loadWorkspaces() }
    }

    // MARK: - 结果视图

    @ViewBuilder
    private var phaseView: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Backing up, please wait...")).foregroundStyle(.secondary).font(.subheadline)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

        case .success(let result):
            VStack(alignment: .leading, spacing: 8) {
                Label(L("Backup Succeeded"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline).bold().foregroundStyle(.green)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text(L("OpenClaw Version")).foregroundStyle(.secondary)
                        Text(result.meta.openClawVersion).font(.system(.caption, design: .monospaced))
                    }
                    GridRow {
                        Text(L("File Count")).foregroundStyle(.secondary)
                        Text("\(result.meta.fileCount) \(L("files"))")
                    }
                    GridRow {
                        Text(L("Backup Size")).foregroundStyle(.secondary)
                        Text(Formatters.byteCount(result.meta.sizeBytes))
                    }
                    GridRow {
                        Text(L("Elapsed")).foregroundStyle(.secondary)
                        Text(String(format: "%.2f \(L("seconds"))", result.elapsed))
                    }
                    GridRow {
                        Text(L("Archive ID")).foregroundStyle(.secondary)
                        Text(result.meta.archiveId).font(.system(.caption, design: .monospaced))
                    }
                }
                .font(.caption)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.green.opacity(0.2), lineWidth: 1))

        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(L("Backup Failed"), systemImage: "xmark.circle.fill")
                    .font(.subheadline).bold().foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func loadWorkspaces() {
        let discovered = OpenClawPaths.discoverWorkspaces()
        workspacePaths = discovered.map { WorkspacePath(url: $0.url) }
    }

    private func commitAddingPath() {
        let path = addingPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard !workspacePaths.contains(where: { $0.url == url }) else { return }
        workspacePaths.append(WorkspacePath(url: url))
        addingPath = ""
    }

    private func chooseDirectory(for target: DirectoryTarget) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Select")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch target {
        case .state:
            customStatePath = url.path
            UserDefaults.standard.set(url.path, forKey: "lastCustomStatePath")
        case .workspace:
            addingPath = url.path
        }
    }

    private func runBackup() {
        phase = .running
        let request = BackupRequest(
            stateURL: stateURL,
            workspaceURLs: workspacePaths.map { $0.url },
            label: customLabel.isEmpty ? nil : customLabel
        )
        Task {
            do {
                let service = LocalBackupService()
                let result = try await Task.detached(priority: .userInitiated) {
                    try service.createManualBackup(request: request)
                }.value
                archiveStore.refresh()
                phase = .success(result)
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }

    private enum DirectoryTarget { case state, workspace }
}

// MARK: - SectionBlock

private struct SectionBlock<Content: View>: View {
    let title: String
    let footnote: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 辅助模型

private struct WorkspacePath: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - BackupPhase

private enum BackupPhase: Equatable {
    case idle
    case running
    case success(BackupOperationResult)
    case failure(String)

    static func == (lhs: BackupPhase, rhs: BackupPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.running, .running): return true
        case (.success, .success): return true
        case (.failure(let a), .failure(let b)): return a == b
        default: return false
        }
    }
}
