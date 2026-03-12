import SwiftUI

@main
struct BackClawApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var archiveStore = ArchiveStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(archiveStore)
                .frame(minWidth: 960, minHeight: 640)
                .background(ToolbarSidebarButtonRemover())
                .id(appState.languageRefreshId)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .id(appState.languageRefreshId)
        }
    }
}

// MARK: - 移除侧边栏切换按钮

private struct ToolbarSidebarButtonRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> _RemoverView { _RemoverView() }
    func updateNSView(_ nsView: _RemoverView, context: Context) {}

    class _RemoverView: NSView {
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let toolbar = window?.toolbar else { return }
            removeSidebarButton(from: toolbar)
            observation = toolbar.observe(\.items, options: [.new]) { [weak self] tb, _ in
                DispatchQueue.main.async { self?.removeSidebarButton(from: tb) }
            }
        }

        private func removeSidebarButton(from toolbar: NSToolbar) {
            let sidebarIDs: [NSToolbarItem.Identifier] = [
                NSToolbarItem.Identifier("com.apple.SwiftUI.navigationSplitView.toggleSidebar"),
                NSToolbarItem.Identifier("NSToolbarToggleSidebarItem"),
            ]
            for id in sidebarIDs {
                while let idx = toolbar.items.firstIndex(where: { $0.itemIdentifier == id }) {
                    toolbar.removeItem(at: idx)
                }
            }
        }
    }
}
