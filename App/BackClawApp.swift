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
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.removeSidebarButton()
            }
        }

        private func removeSidebarButton() {
            guard let toolbar = window?.toolbar else { return }
            let targets = toolbar.items.filter {
                $0.itemIdentifier.rawValue.lowercased().contains("sidebar") ||
                $0.itemIdentifier.rawValue.lowercased().contains("toggle")
            }
            for item in targets {
                if let idx = toolbar.items.firstIndex(of: item) {
                    toolbar.removeItem(at: idx)
                }
            }
        }
    }
}
