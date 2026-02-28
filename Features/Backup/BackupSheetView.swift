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

            // ── 标题 ──────────────────────────────────────────
            Text("立即备份")
                .font(.title2).bold()
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()

            // ── 内容区 ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 18) {

                // State 目录
                SectionBlock(title: "State 目录", footnote: "包含配置、凭证、sessions 及所有 agent 数据。") {
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
                            Button("自定义") { useCustomState = true }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        HStack(spacing: 6) {
                            TextField("State 目录路径", text: $customStatePath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .disabled(phase == .running)
                            Button("选择…") { chooseDirectory(for: .state) }
                                .disabled(phase == .running)
                            Button("重置") {
                                useCustomState = false
                                customStatePath = ""
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                // Workspace 目录
                SectionBlock(title: "Workspace 目录", footnote: "包含记忆、技能文件。多 agent 场景下每个 agent 有独立 workspace。") {
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
                            TextField("添加 Workspace 路径…", text: $addingPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .disabled(phase == .running)
                            Button("浏览…") { chooseDirectory(for: .workspace) }
                                .disabled(phase == .running)
                            Button("添加") { commitAddingPath() }
                                .disabled(addingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .running)
                        }
                    }
                }

                // 备份标签
                SectionBlock(title: "备份标签（可选）", footnote: "附加到存档 ID 末尾，仅支持字母、数字、连字符。") {
                    TextField("例如：upgrade-before-v2", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .disabled(phase == .running)
                }

                // 结果区
                if phase != .idle {
                    phaseView
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Spacer(minLength: 0)

            Divider()

            // ── 底部按钮 ──────────────────────────────────────
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .disabled(phase == .running)
                    .keyboardShortcut(.escape, modifiers: [])

                Button {
                    runBackup()
                } label: {
                    if phase == .running {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("备份中…")
                        }
                    } else {
                        Text("开始备份")
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
                Text("正在备份，请稍候…").foregroundStyle(.secondary).font(.subheadline)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

        case .success(let result):
            VStack(alignment: .leading, spacing: 8) {
                Label("备份成功", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).bold().foregroundStyle(.green)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("OpenClaw 版本").foregroundStyle(.secondary)
                        Text(result.meta.openClawVersion).font(.system(.caption, design: .monospaced))
                    }
                    GridRow {
                        Text("文件数").foregroundStyle(.secondary)
                        Text("\(result.meta.fileCount) 个文件")
                    }
                    GridRow {
                        Text("备份大小").foregroundStyle(.secondary)
                        Text(Formatters.byteCount(result.meta.sizeBytes))
                    }
                    GridRow {
                        Text("耗时").foregroundStyle(.secondary)
                        Text(String(format: "%.2f 秒", result.elapsed))
                    }
                    GridRow {
                        Text("存档 ID").foregroundStyle(.secondary)
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
                Label("备份失败", systemImage: "xmark.circle.fill")
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
        panel.prompt = "选择"
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
