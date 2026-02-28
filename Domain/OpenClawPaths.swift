import Foundation

/// OpenClaw 路径与版本解析
/// 官方文档：https://docs.openclaw.ai/help/environment
enum OpenClawPaths {

    // MARK: - State 目录

    /// 默认 `~/.openclaw/`，可被 OPENCLAW_STATE_DIR / OPENCLAW_HOME 覆盖
    static var stateDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        if let v = env["OPENCLAW_STATE_DIR"], !v.isEmpty {
            return URL(fileURLWithPath: (v as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let h = env["OPENCLAW_HOME"], !h.isEmpty {
            return URL(fileURLWithPath: (h as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent(".openclaw", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
    }

    static var stateDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: stateDirectory.path)
    }

    // MARK: - 版本号

    /// 读取 OpenClaw 版本号，按优先级依次尝试多个来源。
    static var openClawVersion: String {
        // 1. CLI: `openclaw --version`（最准确，直接反映当前安装版本）
        if let v = runCLI(args: ["--version"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !v.isEmpty {
            return v.hasPrefix("v") ? v : "v\(v)"
        }

        // 2. npm 全局安装目录下的 package.json
        let npmRoots = [
            "/usr/local/lib/node_modules/openclaw/package.json",
            "/opt/homebrew/lib/node_modules/openclaw/package.json",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/share/npm/lib/node_modules/openclaw/package.json",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/lib/node_modules/openclaw/package.json"
        ]
        for path in npmRoots {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let v = json["version"] as? String, !v.isEmpty {
                return v.hasPrefix("v") ? v : "v\(v)"
            }
        }

        // 3. ~/.openclaw/package.json（旧版本可能存在）
        let pkgURL = stateDirectory.appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: pkgURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = json["version"] as? String, !v.isEmpty {
            return v.hasPrefix("v") ? v : "v\(v)"
        }

        // 4. ~/.openclaw/VERSION 纯文本文件
        let versionFileURL = stateDirectory.appendingPathComponent("VERSION")
        if let v = try? String(contentsOf: versionFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            return v.hasPrefix("v") ? v : "v\(v)"
        }

        return "unknown"
    }

    // MARK: - Workspace 发现

    /// 自动发现所有 workspace 目录（含多 agent 场景）
    static func discoverWorkspaces() -> [OpenClawWorkspace] {
        var results: [OpenClawWorkspace] = []
        let config = loadConfig()

        // 1. agents.list[].workspace（多 agent）
        if let agentsList = config?["agents"] as? [String: Any],
           let list = agentsList["list"] as? [[String: Any]] {
            for agent in list {
                let agentId = agent["id"] as? String ?? "unknown"
                if let wsPath = agent["workspace"] as? String, !wsPath.isEmpty {
                    let url = URL(fileURLWithPath: (wsPath as NSString).expandingTildeInPath, isDirectory: true)
                    results.append(OpenClawWorkspace(
                        id: "agent-\(agentId)",
                        agentId: agentId,
                        url: url,
                        isDefault: false
                    ))
                }
            }
        }

        // 2. agent.workspace（单 agent 全局配置）
        if let agentBlock = config?["agent"] as? [String: Any],
           let wsPath = agentBlock["workspace"] as? String, !wsPath.isEmpty {
            let url = URL(fileURLWithPath: (wsPath as NSString).expandingTildeInPath, isDirectory: true)
            if !results.contains(where: { $0.url == url }) {
                results.append(OpenClawWorkspace(
                    id: "default",
                    agentId: "main",
                    url: url,
                    isDefault: true
                ))
            }
        }

        // 3. 默认路径 fallback
        let defaultURL = stateDirectory.appendingPathComponent("workspace", isDirectory: true)
        if results.isEmpty || !results.contains(where: { $0.url == defaultURL }) {
            results.insert(OpenClawWorkspace(
                id: "default",
                agentId: "main",
                url: defaultURL,
                isDefault: true
            ), at: 0)
        }

        // 4. OPENCLAW_PROFILE 衍生的 workspace-<profile>
        if let profile = ProcessInfo.processInfo.environment["OPENCLAW_PROFILE"],
           !profile.isEmpty, profile != "default" {
            let profileURL = stateDirectory.appendingPathComponent("workspace-\(profile)", isDirectory: true)
            if !results.contains(where: { $0.url == profileURL }) {
                results.append(OpenClawWorkspace(
                    id: "profile-\(profile)",
                    agentId: profile,
                    url: profileURL,
                    isDefault: false
                ))
            }
        }

        return results
    }

    // MARK: - 私有工具

    private static func configURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let p = env["OPENCLAW_CONFIG_PATH"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return stateDirectory.appendingPathComponent("openclaw.json")
    }

    private static func loadConfig() -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL()) else { return nil }
        // openclaw.json 是 JSON5，先尝试标准 JSON 解析（大多数配置兼容）
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func runCLI(args: [String]) -> String? {
        let candidates = [
            "/usr/local/bin/openclaw",
            "/opt/homebrew/bin/openclaw",
            "/usr/bin/openclaw",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/openclaw"
        ]
        guard let bin = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: bin)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        // 超时 3 秒，避免永久阻塞主线程
        let deadline = Date().addingTimeInterval(3)
        while task.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if task.isRunning {
            task.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Workspace 描述模型

struct OpenClawWorkspace: Identifiable, Equatable {
    let id: String
    let agentId: String
    let url: URL
    let isDefault: Bool

    var displayName: String {
        isDefault && agentId == "main" ? "主 Workspace" : "Workspace (\(agentId))"
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
