import SwiftUI

struct ArchivePreviewView: View {
    let archive: BackupArchive

    @EnvironmentObject private var archiveStore: ArchiveStore
    @StateObject private var vm = ArchivePreviewViewModel()
    @State private var selectedFileURL: URL?
    @State private var sidebarWidth: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            MetaSummaryBar(archive: archive)
            Divider()

            HStack(spacing: 0) {
                // 左：目录树（可拖拽宽度）
                treePanel
                    .frame(width: sidebarWidth)

                // 拖拽分隔条
                ResizeDivider(width: $sidebarWidth, minWidth: 180, maxWidth: 600)

                // 右：文件预览
                previewPanel
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(archive.meta.archiveId)
        .navigationSubtitle(Formatters.dateTime(archive.meta.createdAt))
        .onAppear {
            vm.reset()
            vm.loadTree(at: archive.payloadURL)
        }
        .onChange(of: selectedFileURL) { newURL in
            guard let url = newURL else { return }
            vm.previewFile(at: url)
        }
    }

    // MARK: - 目录树面板

    private var treePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L("File Structure"), systemImage: "folder.badge.gearshape")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if vm.isLoadingTree {
                Spacer()
                ProgressView(L("Loading...")).padding()
                Spacer()
            } else if let err = vm.treeError {
                EmptyStateView(title: L("Cannot Load Directory"), systemImage: "exclamationmark.triangle", description: err)
            } else if vm.tree.isEmpty {
                EmptyStateView(title: L("Backup is Empty"), systemImage: "tray", description: L("This backup contains no files"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(vm.tree, id: \.id) { node in
                            if node.isSection {
                                SectionGroupRow(node: node, selectedFileURL: $selectedFileURL)
                            } else {
                                FileTreeRow(node: node, depth: 0, selectedFileURL: $selectedFileURL)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 文件预览面板

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label(
                    selectedFileURL?.lastPathComponent ?? L("File Preview"),
                    systemImage: "doc.text"
                )
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if vm.isLoadingFile {
                Spacer()
                ProgressView(L("Reading...")).padding()
                Spacer()
            } else if let err = vm.previewError {
                EmptyStateView(title: L("Cannot Preview"), systemImage: "doc.questionmark", description: err)
            } else if let attributed = vm.highlightedContent {
                CodeTextView(attributedText: attributed)
            } else {
                EmptyStateView(title: L("No File Selected"), systemImage: "doc", description: L("Select a file from the tree to preview"))
            }
        }
    }
}

// MARK: - 可拖拽分隔条

private struct ResizeDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                isDragging = true
                                let newWidth = width + value.translation.width
                                width = min(max(newWidth, minWidth), maxWidth)
                            }
                            .onEnded { _ in isDragging = false }
                    )
            )
            .background(isDragging ? Color.accentColor.opacity(0.3) : Color.clear)
    }
}

// MARK: - VSCode 风格 Section 折叠区

private struct SectionGroupRow: View {
    let node: PreviewNode
    @Binding var selectedFileURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 标题行（纯展示，不可折叠）
            HStack(spacing: 6) {
                Text(node.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            ForEach(node.children, id: \.id) { child in
                FileTreeRow(node: child, depth: 0, selectedFileURL: $selectedFileURL)
            }
        }
    }
}

// MARK: - 普通文件/目录行

private struct FileTreeRow: View {
    let node: PreviewNode
    let depth: Int
    @Binding var selectedFileURL: URL?
    @State private var isExpanded = false

    private var isSelected: Bool { selectedFileURL == node.url }
    private var indent: CGFloat { CGFloat(depth) * 14 + 20 }

    var body: some View {
        if node.isDirectory {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Spacer().frame(width: indent)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(node.name)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(node.children, id: \.id) { child in
                        FileTreeRow(node: child, depth: depth + 1, selectedFileURL: $selectedFileURL)
                    }
                }
            }
        } else {
            Button {
                selectedFileURL = node.url
            } label: {
                HStack(spacing: 4) {
                    Spacer().frame(width: indent + 14)
                    Image(systemName: fileIcon(for: node.name))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(node.name)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Color(NSColor.selectedControlTextColor) : .primary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func fileIcon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "json":        return "curlybraces"
        case "yaml", "yml": return "doc.plaintext"
        case "conf", "ini": return "gearshape"
        case "txt", "log":  return "doc.text"
        case "xml":         return "chevron.left.forwardslash.chevron.right"
        case "md":          return "doc.richtext"
        case "env":         return "key"
        default:            return "doc"
        }
    }
}

// MARK: - 元数据摘要条

private struct MetaSummaryBar: View {
    let archive: BackupArchive

    private var compatibility: VersionCompatibility {
        archive.meta.versionCompatibility()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                MetaItem(icon: "doc.on.doc",    label: L("File Count"),        value: "\(archive.meta.fileCount)")
                MetaItem(icon: "internaldrive", label: L("Size"),               value: Formatters.byteCount(archive.meta.sizeBytes))
                MetaItem(icon: "shippingbox",   label: L("OpenClaw Version"),   value: archive.meta.openClawVersion)
                MetaItem(icon: "tag",           label: L("Type"),               value: archive.meta.backupType.rawValue)
                MetaItem(
                    icon: archive.meta.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill",
                    label: L("Status"),
                    value: archive.meta.status == .success ? L("Success") : L("Failed"),
                    valueColor: archive.meta.status == .success ? .green : .red
                )
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if let warning = compatibility.warningMessage {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: compatibility.requiresStrongWarning
                          ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(compatibility.requiresStrongWarning ? .red : .orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(compatibility.requiresStrongWarning ? .red : .primary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(compatibility.requiresStrongWarning
                            ? Color.red.opacity(0.07) : Color.orange.opacity(0.07))
            }
        }
        .background(.bar)
    }
}

private struct MetaItem: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(.secondary).imageScale(.small)
                Text(label).foregroundStyle(.secondary)
            }
            .font(.caption)
            Text(value).font(.subheadline).bold().foregroundStyle(valueColor)
        }
    }
}

// MARK: - 鼠标指针扩展

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
