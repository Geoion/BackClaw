import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @State private var showBackupSheet = false
    @State private var showExportSheet = false
    @State private var showRestoreSheet = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var selectedArchiveID: String?

    private let importService = ImportService()

    private var selectedArchive: BackupArchive? {
        archiveStore.archives.first(where: { $0.id == selectedArchiveID })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ArchiveSidebarView(selectedArchiveID: $selectedArchiveID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 360, max: 600)
        } detail: {
            if let archive = selectedArchive {
                ArchivePreviewView(archive: archive)
                    .environmentObject(archiveStore)
            } else {
                EmptyDetailView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .toolbar(id: "mainToolbar") {
            ToolbarItem(id: "refresh", placement: .primaryAction) {
                ToolbarButton(title: L("Refresh"), systemImage: "arrow.clockwise") {
                    archiveStore.refresh()
                }
                .help(L("Refresh backup list"))
            }

            ToolbarItem(id: "import", placement: .primaryAction) {
                ToolbarButton(
                    title: isImporting ? L("Importing...") : L("Import Backup"),
                    systemImage: "square.and.arrow.down",
                    isLoading: isImporting
                ) {
                    pickImportFile()
                }
                .disabled(isImporting)
                .help(L("Import a backup from tar.gz or zip"))
            }

            ToolbarItem(id: "export", placement: .primaryAction) {
                ToolbarButton(title: L("Export"), systemImage: "square.and.arrow.up") {
                    showExportSheet = true
                }
                .disabled(selectedArchive == nil)
                .help(L("Export as Archive"))
            }

            ToolbarItem(id: "restore", placement: .primaryAction) {
                ToolbarButton(title: L("Restore"), systemImage: "arrow.counterclockwise") {
                    showRestoreSheet = true
                }
                .disabled(selectedArchive == nil)
                .help(L("Restore this backup to OpenClaw data directory"))
            }

            ToolbarItem(id: "backup", placement: .primaryAction) {
                ToolbarButton(
                    title: L("Backup Now"),
                    systemImage: "externaldrive.badge.plus",
                    isProminent: true
                ) {
                    showBackupSheet = true
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .help(L("Backup Now Shortcut Help"))
            }
        }
        .sheet(isPresented: $showBackupSheet) {
            BackupSheetView(isPresented: $showBackupSheet)
                .environmentObject(archiveStore)
        }
        .sheet(isPresented: $showExportSheet) {
            if let archive = selectedArchive {
                ExportSheetView(archive: archive, isPresented: $showExportSheet)
            }
        }
        .sheet(isPresented: $showRestoreSheet) {
            if let archive = selectedArchive {
                RestoreSheetView(archive: archive, isPresented: $showRestoreSheet)
                    .environmentObject(archiveStore)
            }
        }
        .alert(L("Import Failed"), isPresented: $showImportError) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(importError ?? L("Unknown Error"))
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
        panel.title = L("Select Backup File")
        panel.message = L("Select a .tar.gz or .zip exported by BackClaw")
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

// MARK: - ToolbarButton

private struct ToolbarButton: View {
    let title: String
    let systemImage: String
    var isLoading: Bool = false
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        if isProminent {
            Button(action: action) { label }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) { label }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
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
