import AppKit
import SwiftUI

struct RestoreSheetView: View {
    let archive: BackupArchive
    @Binding var isPresented: Bool
    @EnvironmentObject private var archiveStore: ArchiveStore

    // 三步确认状态
    @State private var step1Checked = false       // 第一步：勾选理解风险
    @State private var step2Checked = false       // 第二步：勾选理解覆盖
    @State private var confirmText = ""           // 第三步：输入 RESTORE
    @State private var createPreSnapshot = true
    @State private var phase: RestorePhase = .confirm

    private let service = RestoreService()
    private let requiredWord = "RESTORE"

    private var compatibility: VersionCompatibility {
        archive.meta.versionCompatibility()
    }

    private var allStepsComplete: Bool {
        step1Checked && step2Checked && confirmText == requiredWord && phase == .confirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 标题
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("还原备份")
                    .font(.title2).bold()
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            VStack(alignment: .leading, spacing: 20) {

                // 存档信息
                VStack(alignment: .leading, spacing: 6) {
                    Text("目标存档")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary).textCase(.uppercase)
                    HStack(spacing: 8) {
                        Image(systemName: "archivebox")
                            .foregroundStyle(.secondary).imageScale(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(archive.meta.archiveId)
                                .font(.system(.subheadline, design: .monospaced))
                            Text("\(Formatters.dateTime(archive.meta.createdAt)) · \(archive.meta.fileCount) 个文件 · \(Formatters.byteCount(archive.meta.sizeBytes))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // 版本兼容性警告
                if let warning = compatibility.warningMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: compatibility.requiresStrongWarning
                              ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .foregroundStyle(compatibility.requiresStrongWarning ? .red : .orange)
                            .padding(.top, 1)
                        Text(warning)
                            .font(.subheadline)
                            .foregroundStyle(compatibility.requiresStrongWarning ? .red : .primary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        compatibility.requiresStrongWarning ? Color.red.opacity(0.07) : Color.orange.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(compatibility.requiresStrongWarning ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1))
                }

                // 还原前快照开关
                Toggle(isOn: $createPreSnapshot) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("还原前创建快照（强烈推荐）")
                            .font(.subheadline).fontWeight(.medium)
                        Text("自动备份当前 OpenClaw 数据，还原失败时可从快照恢复")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(phase != .confirm)

                Divider()

                // ── 三步确认区 ──────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    Text("请完成以下三步确认才能执行还原")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary).textCase(.uppercase)

                    // 第一步
                    ConfirmCheckRow(
                        step: 1,
                        isChecked: $step1Checked,
                        isDisabled: phase != .confirm,
                        label: "我了解此操作将覆盖当前 OpenClaw 数据目录，操作不可撤销。"
                    )

                    // 第二步
                    ConfirmCheckRow(
                        step: 2,
                        isChecked: $step2Checked,
                        isDisabled: !step1Checked || phase != .confirm,
                        label: "我了解还原后当前所有未备份的数据将被永久覆盖，无法恢复。"
                    )

                    // 第三步：输入确认词
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(confirmText == requiredWord ? Color.red : Color(NSColor.controlColor))
                                .frame(width: 22, height: 22)
                            Text("3")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(confirmText == requiredWord ? .white : .secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("在下方输入 \(requiredWord) 以最终确认")
                                .font(.subheadline)
                                .foregroundStyle(!step2Checked ? .secondary : .primary)
                            TextField("输入 \(requiredWord)", text: $confirmText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .disabled(!step2Checked || phase != .confirm)
                                .autocorrectionDisabled()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            confirmText == requiredWord ? Color.red.opacity(0.6) :
                                            (!confirmText.isEmpty ? Color.orange.opacity(0.5) : Color.clear),
                                            lineWidth: 1.5
                                        )
                                )
                        }
                    }
                    .opacity(!step2Checked ? 0.5 : 1)
                }
                .padding(14)
                .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.15), lineWidth: 1))

                // 结果区
                if phase != .confirm {
                    phaseView
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Spacer(minLength: 0)
            Divider()

            // 底部按钮
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .disabled(phase == .restoring)
                    .keyboardShortcut(.escape, modifiers: [])

                Button {
                    showFinalAlert()
                } label: {
                    if phase == .restoring {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("还原中…")
                        }
                    } else {
                        Label("开始还原", systemImage: "arrow.counterclockwise.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!allStepsComplete)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 结果视图

    @ViewBuilder
    private var phaseView: some View {
        switch phase {
        case .confirm:
            EmptyView()

        case .restoring:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在还原，请稍候…").foregroundStyle(.secondary).font(.subheadline)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

        case .success(let result):
            VStack(alignment: .leading, spacing: 10) {
                Label("还原成功", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).bold().foregroundStyle(.green)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("覆盖文件数").foregroundStyle(.secondary)
                        Text("\(result.copiedFileCount) 个文件")
                    }
                    GridRow {
                        Text("耗时").foregroundStyle(.secondary)
                        Text(String(format: "%.2f 秒", result.elapsed))
                    }
                    if let snapshotId = result.preSnapshotArchiveId {
                        GridRow {
                            Text("还原前快照").foregroundStyle(.secondary)
                            Text(snapshotId).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .font(.caption)

                if result.hasErrors {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("以下文件还原失败：")
                            .font(.caption).bold().foregroundStyle(.orange)
                        ForEach(result.failedItems.prefix(5), id: \.relativePath) { item in
                            Text("• \(item.relativePath)：\(item.reason)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if result.failedItems.count > 5 {
                            Text("…还有 \(result.failedItems.count - 5) 个文件失败")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.green.opacity(0.2), lineWidth: 1))

        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("还原失败", systemImage: "xmark.circle.fill")
                    .font(.subheadline).bold().foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - 第三次确认：系统 Alert

    private func showFinalAlert() {
        guard allStepsComplete else { return }

        let alert = NSAlert()
        alert.messageText = "最终确认：执行还原？"
        alert.informativeText = "此操作将立即覆盖 OpenClaw 数据目录（\(OpenClawPaths.stateDirectory.path)），无法撤销。\n\n确认继续？"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "立即还原")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            runRestore()
        }
    }

    // MARK: - 执行还原

    private func runRestore() {
        phase = .restoring
        let snap = createPreSnapshot
        let arch = archive
        Task {
            do {
                let result = try await service.restore(archive: arch, createPreSnapshot: snap)
                archiveStore.refresh()
                phase = .success(result)
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }
}

// MARK: - 确认勾选行

private struct ConfirmCheckRow: View {
    let step: Int
    @Binding var isChecked: Bool
    let isDisabled: Bool
    let label: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isChecked ? Color.red : Color(NSColor.controlColor))
                    .frame(width: 22, height: 22)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $isChecked) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .disabled(isDisabled)
        }
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Phase

private enum RestorePhase: Equatable {
    case confirm
    case restoring
    case success(RestoreResult)
    case failure(String)

    static func == (lhs: RestorePhase, rhs: RestorePhase) -> Bool {
        switch (lhs, rhs) {
        case (.confirm, .confirm), (.restoring, .restoring): return true
        case (.success, .success): return true
        case (.failure(let a), .failure(let b)): return a == b
        default: return false
        }
    }
}
