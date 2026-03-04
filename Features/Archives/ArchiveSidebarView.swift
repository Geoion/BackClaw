import SwiftUI

struct ArchiveSidebarView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @Binding var selectedArchiveID: String?
    @Binding var showBackupSheet: Bool
    let isImporting: Bool
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            listContent
        }
        .navigationTitle(L("Backup Records"))
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            SidebarButton(
                title: L("Refresh"),
                systemImage: "arrow.clockwise",
                help: L("Refresh backup list")
            ) {
                archiveStore.refresh()
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

    private var listContent: some View {
        List(archiveStore.archives, selection: $selectedArchiveID) { archive in
            ArchiveRowView(archive: archive)
                .tag(archive.id)
        }
        .overlay {
            if archiveStore.archives.isEmpty {
                EmptyStateView(
                    title: L("No Backups"),
                    systemImage: "archivebox",
                    description: L("Click \"Backup Now\" in the toolbar to create your first backup")
                )
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(archive.meta.archiveId)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: archive.meta.status)
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
