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

    private var selectedArchive: BackupArchive? {
        archiveStore.archives.first(where: { $0.id == selectedArchiveID })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ArchiveSidebarView(
                selectedArchiveID: $selectedArchiveID,
                showBackupSheet: $showBackupSheet,
                isImporting: isImporting,
                onImport: pickImportFile
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 360, max: 600)
        } detail: {
            if let archive = selectedArchive {
                ArchivePreviewView(archive: archive, onDeleted: {
                    selectedArchiveID = nil
                })
                .environmentObject(archiveStore)
            } else {
                EmptyDetailView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .sheet(isPresented: $showBackupSheet) {
            BackupSheetView(isPresented: $showBackupSheet)
                .environmentObject(archiveStore)
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

