import AppKit
import SwiftUI

struct RestoreSheetView: View {
    let archive: BackupArchive
    @Binding var isPresented: Bool
    @EnvironmentObject private var archiveStore: ArchiveStore

    @State private var step1Checked = false
    @State private var step2Checked = false
    @State private var confirmText = ""
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

            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text(L("Restore Backup"))
                    .font(.title2).bold()
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Target Archive"))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary).textCase(.uppercase)
                    HStack(spacing: 8) {
                        Image(systemName: "archivebox")
                            .foregroundStyle(.secondary).imageScale(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(archive.meta.archiveId)
                                .font(.system(.subheadline, design: .monospaced))
                            Text("\(Formatters.dateTime(archive.meta.createdAt)) · \(archive.meta.fileCount) \(L("files")) · \(Formatters.byteCount(archive.meta.sizeBytes))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

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

                Toggle(isOn: $createPreSnapshot) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Create snapshot before restore (strongly recommended)"))
                            .font(.subheadline).fontWeight(.medium)
                        Text(L("Automatically backs up current OpenClaw data. Recoverable if restore fails."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(phase != .confirm)

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Complete all three steps below to proceed"))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary).textCase(.uppercase)

                    ConfirmCheckRow(
                        step: 1,
                        isChecked: $step1Checked,
                        isDisabled: phase != .confirm,
                        label: L("I understand this will overwrite the current OpenClaw data directory and cannot be undone.")
                    )

                    ConfirmCheckRow(
                        step: 2,
                        isChecked: $step2Checked,
                        isDisabled: !step1Checked || phase != .confirm,
                        label: L("I understand all unbacked data will be permanently overwritten and cannot be recovered.")
                    )

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
                            Text(L("Type RESTORE below to confirm"))
                                .font(.subheadline)
                                .foregroundStyle(!step2Checked ? .secondary : .primary)
                            TextField(L("Type RESTORE"), text: $confirmText)
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

                if phase != .confirm {
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
                    .disabled(phase == .restoring)
                    .keyboardShortcut(.escape, modifiers: [])

                Button {
                    showFinalAlert()
                } label: {
                    if phase == .restoring {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L("Restoring..."))
                        }
                    } else {
                        Label(L("Start Restore"), systemImage: "arrow.counterclockwise.circle.fill")
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
                Text(L("Restoring, please wait...")).foregroundStyle(.secondary).font(.subheadline)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

        case .success(let result):
            VStack(alignment: .leading, spacing: 10) {
                Label(L("Restore Succeeded"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline).bold().foregroundStyle(.green)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text(L("Files Overwritten")).foregroundStyle(.secondary)
                        Text("\(result.copiedFileCount) \(L("files"))")
                    }
                    GridRow {
                        Text(L("Elapsed")).foregroundStyle(.secondary)
                        Text(String(format: "%.2f \(L("seconds"))", result.elapsed))
                    }
                    if let snapshotId = result.preSnapshotArchiveId {
                        GridRow {
                            Text(L("Pre-restore Snapshot")).foregroundStyle(.secondary)
                            Text(snapshotId).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .font(.caption)

                if result.hasErrors {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("The following files failed to restore:"))
                            .font(.caption).bold().foregroundStyle(.orange)
                        ForEach(result.failedItems.prefix(5), id: \.relativePath) { item in
                            Text("• \(item.relativePath)：\(item.reason)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if result.failedItems.count > 5 {
                            Text(String(format: L("...and %d more failed"), result.failedItems.count - 5))
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
                Label(L("Restore Failed"), systemImage: "xmark.circle.fill")
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
        alert.messageText = L("Final Confirmation: Proceed with Restore?")
        alert.informativeText = String(format: L("This will immediately overwrite the OpenClaw data directory (%@). This cannot be undone.\n\nContinue?"), OpenClawPaths.stateDirectory.path)
        alert.alertStyle = .critical
        alert.addButton(withTitle: L("Restore Now"))
        alert.addButton(withTitle: L("Cancel"))

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
