import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @State private var showBackupSheet = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var selectedArchiveID: String?

    private let importService = ImportService()

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ArchiveSidebarView(selectedArchiveID: $selectedArchiveID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 360, max: 600)
        } detail: {
            if let selected = archiveStore.archives.first(where: { $0.id == selectedArchiveID }) {
                ArchivePreviewView(archive: selected)
                    .environmentObject(archiveStore)
            } else {
                EmptyDetailView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .toolbar(id: "mainToolbar") {
            ToolbarItem(id: "refresh", placement: .primaryAction) {
                Button {
                    archiveStore.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新备份列表")
            }
            ToolbarItem(id: "import", placement: .primaryAction) {
                Button {
                    pickImportFile()
                } label: {
                    if isImporting {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("导入中…")
                        }
                    } else {
                        Label("导入备份", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isImporting)
                .help("从 tar.gz 或 zip 文件导入备份")
            }
            ToolbarItem(id: "backup", placement: .primaryAction) {
                Button {
                    showBackupSheet = true
                } label: {
                    Label("立即备份", systemImage: "externaldrive.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .help("立即备份（⇧⌘B）")
            }
        }
        .sheet(isPresented: $showBackupSheet) {
            BackupSheetView(isPresented: $showBackupSheet)
                .environmentObject(archiveStore)
        }
        .alert("导入失败", isPresented: $showImportError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importError ?? "未知错误")
        }
        .onAppear {
            archiveStore.refresh()
            if selectedArchiveID == nil {
                selectedArchiveID = archiveStore.archives.first?.id
            }
        }
        .onChange(of: archiveStore.archives) { _, archives in
            if selectedArchiveID == nil {
                selectedArchiveID = archives.first?.id
            }
        }
    }

    // MARK: - 导入

    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.title = "选择备份文件"
        panel.message = "选择 BackClaw 导出的 .tar.gz 或 .zip 文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .init(filenameExtension: "gz")!]

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        isImporting = true
        Task {
            do {
                let result = try await importService.importArchive(from: fileURL)
                archiveStore.refresh()
                selectedArchiveID = result.archive.id
                isImporting = false
            } catch {
                importError = error.localizedDescription
                showImportError = true
                isImporting = false
            }
        }
    }
}
