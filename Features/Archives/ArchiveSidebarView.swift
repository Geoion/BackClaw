import SwiftUI

struct ArchiveSidebarView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @Binding var selectedArchiveID: String?
    @Binding var showBackupSheet: Bool
    let isImporting: Bool
    let onImport: () -> Void
    @State private var assistantFilter: AssistantFilter = .all
    @State private var currentOpenClawVersion: String = OpenClawPaths.openClawVersion

    private var filteredArchives: [BackupArchive] {
        archiveStore.archives.filter { assistantFilter.matches($0.meta.assistantProduct) }
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            filterBar
            Divider()
            listContent
        }
        .navigationTitle(L("Backup Records"))
        .onAppear {
            ensureVisibleSelection()
        }
        .onChange(of: assistantFilter) { _, _ in
            ensureVisibleSelection()
        }
        .onChange(of: archiveStore.archives) { _, _ in
            ensureVisibleSelection()
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            SidebarButton(
                title: L("Refresh"),
                systemImage: "arrow.clockwise",
                help: L("Refresh backup list")
            ) {
                archiveStore.refresh()
                currentOpenClawVersion = OpenClawPaths.openClawVersion
            }
            SidebarButton(
                title: isImporting ? L("Importing...") : L("Import"),
                systemImage: "square.and.arrow.down",
                help: L("Import a backup from tar.gz or zip"),
                isLoading: isImporting
            ) {
                onImport()
            }
            .disabled(isImporting)

            Spacer()

            SidebarButton(
                title: L("Backup"),
                systemImage: "externaldrive.badge.plus",
                help: L("Backup Now Shortcut Help"),
                isProminent: true
            ) {
                showBackupSheet = true
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Label(L("Assistant Filter"), systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $assistantFilter) {
                ForEach(AssistantFilter.allCases, id: \.self) { filter in
                    Text(L(filter.shortTitleKey)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 7)
    }

    private var listContent: some View {
        List(filteredArchives, selection: $selectedArchiveID) { archive in
            ArchiveRowView(
                archive: archive,
                versionRelation: versionRelation(for: archive.meta.openClawVersion),
                currentOpenClawVersion: currentOpenClawVersion
            )
                .tag(archive.id)
        }
        .overlay {
            if filteredArchives.isEmpty {
                EmptyStateView(
                    title: archiveStore.archives.isEmpty ? L("No Backups") : L("No Backups Match Filter"),
                    systemImage: archiveStore.archives.isEmpty ? "archivebox" : "line.3.horizontal.decrease.circle",
                    description: archiveStore.archives.isEmpty
                        ? L("Click \"Backup Now\" in the toolbar to create your first backup")
                        : L("Try changing assistant filter, or create/import backups")
                )
            }
        }
    }

    private func ensureVisibleSelection() {
        if let selected = selectedArchiveID,
           filteredArchives.contains(where: { $0.id == selected }) {
            return
        }
        selectedArchiveID = filteredArchives.first?.id
    }

    private func versionRelation(for backupVersion: String) -> SidebarVersionRelation {
        guard let current = normalizedVersion(currentOpenClawVersion),
              let backup = normalizedVersion(backupVersion) else {
            return .unknown
        }
        switch compareVersions(current, backup) {
        case .orderedSame:
            return .same
        case .orderedDescending:
            return .downgrade
        case .orderedAscending:
            return .upgrade
        }
    }

    private func normalizedVersion(_ version: String) -> String? {
        let raw = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.lowercased() != "unknown" else { return nil }
        return raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
    }

    private func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(aParts.count, bParts.count)
        for i in 0..<maxLen {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av > bv ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }
}

private enum AssistantFilter: CaseIterable, Hashable {
    case all
    case openclaw
    case compatible

    var titleKey: String {
        switch self {
        case .all:
            return "All Assistants"
        case .openclaw:
            return "Assistant Product OpenClaw"
        case .compatible:
            return "Assistant Product Compatible"
        }
    }

    var shortTitleKey: String {
        switch self {
        case .all:
            return "All"
        case .openclaw:
            return "Assistant Product OpenClaw"
        case .compatible:
            return "Compatible"
        }
    }

    func matches(_ product: BackupAssistantProduct) -> Bool {
        switch self {
        case .all:
            return true
        case .openclaw:
            return product == .openclaw
        case .compatible:
            return product == .compatible
        }
    }
}

// MARK: - 侧边栏操作按钮

private struct SidebarButton: View {
    let title: String
    let systemImage: String
    var help: String = ""
    var isLoading: Bool = false
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        if isProminent {
            Button(action: action) { label }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .help(help)
        } else {
            Button(action: action) { label }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .help(help)
        }
    }

    private var label: some View {
        Label {
            Text(title)
        } icon: {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
        }
    }
}

private struct ArchiveRowView: View {
    let archive: BackupArchive
    let versionRelation: SidebarVersionRelation
    let currentOpenClawVersion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(archive.meta.archiveId)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    AssistantProductBadge(product: archive.meta.assistantProduct)
                    StatusBadge(status: archive.meta.status)
                }
            }

            Text(Formatters.dateTime(archive.meta.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label(Formatters.byteCount(archive.meta.sizeBytes), systemImage: "internaldrive")
                Label("\(archive.meta.fileCount) \(L("files"))", systemImage: "doc.on.doc")
                if archive.meta.openClawVersion != "unknown" {
                    Label(archive.meta.openClawVersion, systemImage: "shippingbox")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if versionRelation.isMismatch {
                HStack(spacing: 6) {
                    Image(systemName: versionRelation.iconName)
                        .imageScale(.small)
                        .foregroundStyle(versionRelation.color)
                    Text(L("Version Mismatch"))
                        .font(.caption2)
                        .foregroundStyle(versionRelation.color)
                    Text("\(currentOpenClawVersion) ↔ \(archive.meta.openClawVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if archive.meta.status == .failed, let msg = archive.meta.errorMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private enum SidebarVersionRelation {
    case same
    case downgrade
    case upgrade
    case unknown

    var isMismatch: Bool {
        switch self {
        case .downgrade, .upgrade:
            return true
        case .same, .unknown:
            return false
        }
    }

    var color: Color {
        switch self {
        case .downgrade:
            return .red
        case .upgrade:
            return .orange
        case .same, .unknown:
            return .secondary
        }
    }

    var iconName: String {
        switch self {
        case .downgrade, .upgrade:
            return "exclamationmark.triangle.fill"
        case .same, .unknown:
            return "info.circle"
        }
    }
}

private struct AssistantProductBadge: View {
    let product: BackupAssistantProduct

    var body: some View {
        Text(L(product.titleKey))
            .font(.caption2)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    private var foreground: Color {
        switch product {
        case .openclaw:
            return .blue
        case .compatible:
            return .orange
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }

    private var stroke: Color {
        foreground.opacity(0.3)
    }
}

private struct StatusBadge: View {
    let status: BackupStatus

    var body: some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.small)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .imageScale(.small)
        }
    }
}
