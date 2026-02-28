import SwiftUI

struct ArchiveSidebarView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @Binding var selectedArchiveID: String?

    var body: some View {
        List(archiveStore.archives, selection: $selectedArchiveID) { archive in
            ArchiveRowView(archive: archive)
                .tag(archive.id)
        }
        .navigationTitle(L("Backup Records"))
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
