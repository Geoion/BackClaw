import AppKit
import Foundation

/// 将不符合 Sendable 的引用类型安全地跨 actor 边界传递。
/// 调用方需确保对象在传递期间不被并发修改。
struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

struct PreviewNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    /// true 表示这是顶层分区节点（state / workspace），在 UI 里渲染为 VSCode 风格的大折叠区标题
    var isSection: Bool = false
    var children: [PreviewNode] = []
}

@MainActor
final class ArchivePreviewViewModel: ObservableObject {
    @Published var tree: [PreviewNode] = []
    @Published var highlightedContent: NSAttributedString?
    @Published var treeError: String?
    @Published var previewError: String?
    @Published var isLoadingTree = false
    @Published var isLoadingFile = false

    private nonisolated static let textExtensions: Set<String> = [
        // 配置
        "json", "yaml", "yml", "toml", "ini", "conf", "cfg", "env", "xml", "plist",
        // 文档
        "txt", "log", "md", "markdown", "rst",
        // 代码
        "swift", "py", "js", "ts", "jsx", "tsx", "sh", "bash", "zsh",
        "rb", "go", "rs", "java", "kt", "c", "cpp", "h", "cs", "php",
        "html", "htm", "css", "scss", "sql",
        // 无扩展名常见文件
        "dockerfile", "makefile", "gitignore", "gitattributes"
    ]
    private nonisolated static let maxPreviewBytes = 1_000_000

    func loadTree(at payloadURL: URL) {
        guard !isLoadingTree else { return }
        isLoadingTree = true
        treeError = nil
        tree = []

        let url = payloadURL
        Task { [weak self] in
            guard let self else { return }
            do {
                let nodes = try await Task.detached(priority: .userInitiated) {
                    try Self.buildTree(at: url)
                }.value
                self.tree = nodes
                self.isLoadingTree = false
            } catch {
                self.treeError = error.localizedDescription
                self.isLoadingTree = false
            }
        }
    }

    func previewFile(at fileURL: URL) {
        highlightedContent = nil
        previewError = nil
        isLoadingFile = true

        let url = fileURL
        let ext = fileURL.pathExtension
        Task { [weak self] in
            guard let self else { return }
            do {
                // 读取 + 高亮全在后台线程完成，主线程只做赋值
                // 用 SendableBox 绕过 NSAttributedString 的 Sendable 限制
                let box = try await Task.detached(priority: .userInitiated) {
                    let text = try Self.readText(at: url)
                    let attributed = SyntaxHighlighter.highlight(text, fileExtension: ext)
                    return SendableBox(attributed)
                }.value
                self.highlightedContent = box.value
                self.isLoadingFile = false
            } catch {
                self.previewError = error.localizedDescription
                self.isLoadingFile = false
            }
        }
    }

    func reset() {
        tree = []
        highlightedContent = nil
        treeError = nil
        previewError = nil
        isLoadingTree = false
        isLoadingFile = false
    }

    // MARK: - 纯函数，在后台线程执行（nonisolated 脱离 MainActor）

    private nonisolated static func buildTree(at directoryURL: URL) throws -> [PreviewNode] {
        let fm = FileManager.default
        let topItems = try fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var sections: [PreviewNode] = []

        for topURL in topItems {
            let values = try topURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                // payload 根目录下的散文件，直接作为普通节点
                sections.append(PreviewNode(id: topURL.path, name: topURL.lastPathComponent, url: topURL, isDirectory: false))
                continue
            }

            let name = topURL.lastPathComponent

            if name == "workspaces" {
                // workspaces/ 下每个子目录是一个独立 Section
                let wsItems = (try? fm.contentsOfDirectory(
                    at: topURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for wsURL in wsItems.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let children = (try? buildChildren(at: wsURL, fm: fm)) ?? []
                    sections.append(PreviewNode(
                        id: wsURL.path,
                        name: "WORKSPACE: \(wsURL.lastPathComponent)",
                        url: wsURL,
                        isDirectory: true,
                        isSection: true,
                        children: children
                    ))
                }
            } else {
                // state/ 或其他顶层目录作为 Section
                let children = (try? buildChildren(at: topURL, fm: fm)) ?? []
                let displayName = name == "state" ? "STATE" : name.uppercased()
                sections.append(PreviewNode(
                    id: topURL.path,
                    name: displayName,
                    url: topURL,
                    isDirectory: true,
                    isSection: true,
                    children: children
                ))
            }
        }
        return sections
    }

    private nonisolated static func buildChildren(at directoryURL: URL, fm: FileManager) throws -> [PreviewNode] {
        let items = try fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try items
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                let isDir = values.isDirectory == true
                return PreviewNode(
                    id: url.path,
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: isDir,
                    children: isDir ? (try buildChildren(at: url, fm: fm)) : []
                )
            }
    }

    private nonisolated static func readText(at fileURL: URL) throws -> String {
        let ext = fileURL.pathExtension.lowercased()
        let filename = fileURL.lastPathComponent.lowercased()
        // 无扩展名的常见文本文件
        let knownTextFilenames: Set<String> = ["dockerfile", "makefile", ".gitignore", ".gitattributes", ".env", ".envrc", "procfile"]
        let isText = textExtensions.contains(ext) || ext.isEmpty && knownTextFilenames.contains(filename)
        guard isText else {
            throw BackClawError.previewFileNotText
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = attrs[.size] as? Int ?? 0
        guard size <= maxPreviewBytes else {
            throw BackClawError.previewFileTooLarge
        }
        let data = try Data(contentsOf: fileURL)
        return String(data: data, encoding: .utf8) ?? "<文件不是 UTF-8 编码，暂不支持预览>"
    }
}
