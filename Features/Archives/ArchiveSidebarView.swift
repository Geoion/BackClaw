import SwiftUI

struct ArchiveSidebarView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @Binding var selectedArchiveID: String?

    var body: some View {
        List(archiveStore.archives, selection: $selectedArchiveID) { archive in
            ArchiveRowView(archive: archive)
                .tag(archive.id)
        }
        .navigationTitle("备份记录")
        .overlay {
            if archiveStore.archives.isEmpty {
                EmptyStateView(
                    title: "暂无备份",
                    systemImage: "archivebox",
                    description: "点击工具栏「立即备份」创建第一个备份"
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
                Label("\(archive.meta.fileCount) 个文件", systemImage: "doc.on.doc")
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
