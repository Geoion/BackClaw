import AppKit
import Foundation

/// 轻量语法高亮，返回 NSAttributedString，直接喂给 NSTextView。
/// 所有着色在后台线程完成，不阻塞主线程。
enum SyntaxHighlighter {

    static func highlight(_ text: String, fileExtension ext: String) -> NSAttributedString {
        let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let base = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: monoFont,
                .foregroundColor: NSColor.labelColor
            ]
        )
        switch ext.lowercased() {
        case "json":                    applyJSON(to: base)
        case "yaml", "yml":             applyYAML(to: base)
        case "md", "markdown":          applyMarkdown(to: base)
        case "sh", "bash", "zsh":       applyShell(to: base)
        case "py":                      applyPython(to: base)
        case "swift":                   applySwift(to: base)
        case "js", "ts", "jsx", "tsx":  applyJS(to: base)
        case "toml", "ini", "conf", "cfg": applyTOML(to: base)
        case "xml", "html", "htm":      applyXML(to: base)
        default: break
        }
        return base
    }

    // MARK: - JSON

    private static func applyJSON(to s: NSMutableAttributedString) {
        colorize(s, pattern: #""[^"\\]*(?:\\.[^"\\]*)*"\s*:"#,         color: .systemTeal)
        colorize(s, pattern: #":\s*"[^"\\]*(?:\\.[^"\\]*)*""#,         color: .systemGreen)
        colorize(s, pattern: #"\b(true|false|null)\b"#,                  color: .systemOrange)
        colorize(s, pattern: #"\b-?\d+\.?\d*([eE][+-]?\d+)?\b"#,        color: .systemPurple)
    }

    // MARK: - YAML

    private static func applyYAML(to s: NSMutableAttributedString) {
        colorize(s, pattern: #"#.*$"#,                                   color: .systemGray, options: .anchorsMatchLines)
        colorize(s, pattern: #"^[ \t]*[a-zA-Z_][a-zA-Z0-9_\-]*\s*:"#,  color: .systemTeal, options: .anchorsMatchLines)
        colorize(s, pattern: #"'[^']*'"#,                                color: .systemGreen)
        colorize(s, pattern: #""[^"]*""#,                                color: .systemGreen)
        colorize(s, pattern: #"\b(true|false|null|yes|no)\b"#,           color: .systemOrange)
    }

    // MARK: - Markdown

    private static func applyMarkdown(to s: NSMutableAttributedString) {
        // heading — 加粗 + 蓝色
        colorize(s, pattern: #"^#{1,6} .+$"#, color: .systemBlue, options: .anchorsMatchLines) { attr in
            attr[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        }
        colorize(s, pattern: #"`[^`\n]+`"#,                              color: .systemOrange)
        colorize(s, pattern: #"^```[\s\S]*?^```"#,                       color: .systemOrange, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
        colorize(s, pattern: #"\*\*[^*\n]+\*\*"#,                        color: .labelColor) { attr in
            attr[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        }
        colorize(s, pattern: #"\*[^*\n]+\*"#,                            color: .secondaryLabelColor)
        colorize(s, pattern: #"^\s*[-*+] "#,                             color: .systemTeal, options: .anchorsMatchLines)
        colorize(s, pattern: #"^\s*> "#,                                  color: .systemGray, options: .anchorsMatchLines)
        colorize(s, pattern: #"\[[^\]]+\]\([^)]+\)"#,                    color: .systemBlue)
    }

    // MARK: - Shell

    private static func applyShell(to s: NSMutableAttributedString) {
        colorize(s, pattern: #"#.*$"#, color: .systemGray, options: .anchorsMatchLines)
        colorize(s, pattern: #"\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|export|local|echo|exit|source|set|unset|shift|read|declare|readonly|trap|eval|exec)\b"#, color: .systemPink)
        colorize(s, pattern: #""[^"]*""#,                                color: .systemGreen)
        colorize(s, pattern: #"'[^']*'"#,                                color: .systemGreen)
        colorize(s, pattern: #"\$\{?[a-zA-Z_][a-zA-Z0-9_]*\}?"#,        color: .systemOrange)
    }

    // MARK: - Python

    private static func applyPython(to s: NSMutableAttributedString) {
        colorize(s, pattern: #"#.*$"#,                                   color: .systemGray, options: .anchorsMatchLines)
        colorize(s, pattern: #"\"\"\"[\s\S]*?\"\"\""#,                   color: .systemGreen, options: .dotMatchesLineSeparators)
        colorize(s, pattern: #""[^"\\]*(?:\\.[^"\\]*)*""#,               color: .systemGreen)
        colorize(s, pattern: #"'[^'\\]*(?:\\.[^'\\]*)*'"#,               color: .systemGreen)
        colorize(s, pattern: #"\b(def|class|import|from|return|if|elif|else|for|while|in|not|and|or|is|None|True|False|pass|break|continue|with|as|try|except|finally|raise|lambda|yield|async|await|global|nonlocal|del|assert)\b"#, color: .systemPink)
        colorize(s, pattern: #"\b\d+\.?\d*\b"#,                          color: .systemPurple)
        colorize(s, pattern: #"@[a-zA-Z_][a-zA-Z0-9_]*"#,               color: .systemOrange)
    }

    // MARK: - Swift

    private static func applySwift(to s: NSMutableAttributedString) {
        colorize(s, pattern: #"//.*$"#,                                  color: .systemGray, options: .anchorsMatchLines)
        colorize(s, pattern: #"/\*[\s\S]*?\*/"#,                         color: .systemGray, options: .dotMatchesLineSeparators)
        colorize(s, pattern: #""[^"\\]*(?:\\.[^"\\]*)*""#,               color: .systemGreen)
        colorize(s, pattern: #"\b(func|class|struct|enum|protocol|extension|var|let|if|else|guard|return|for|while|in|import|switch|case|default|break|continue|throw|throws|try|catch|init|deinit|self|super|nil|true|false|async|await|actor|nonisolated|where|typealias|associatedtype|some|any|inout|mutating|static|final|open|public|internal|private|fileprivate)\b"#, color: .systemPink)
        colorize(s, pattern: #"@\w+"#,                                   color: .systemOrange)
        colorize(s, pattern: #"\b\d+\.?\d*\b"#,                          color: .systemPurple)
    }

    // MARK: - JS / TS

    private static func applyJS(to s: NSMutableAttributedString) {
        colorize(s, pattern: #"//.*$"#,                                  color: .systemGray, options: .anchorsMatchLines)
        colorize(s, pattern: #"/\*[\s\S]*?\*/"#,                         color: .systemGray, options: .dotMatchesLineSeparators)
        colorize(s, pattern: #"`[^`]*`"#,                                color: .systemGreen)
        colorize(s, pattern: #""[^"\\]*(?:\\.[^"\\]*)*""#,               color: .systemGreen)
        colorize(s, pattern: #"'[^'\\]*(?:\\.[^'\\]*)*'"#,               color: .systemGreen)
        colorize(s, pattern: #"\b(const|let|var|function|class|import|export|from|return|if|else|for|while|in|of|new|this|null|undefined|true|false|async|await|try|catch|finally|throw|typeof|instanceof|interface|type|enum|extends|implements|readonly|abstract|declare)\b"#, color: .systemPink)
        colorize(s, pattern: #"\b\d+\.?\d*\b"#,                          color: .systemPurple)
    }

    // MARK: - TOML / INI

    private static func applyTOML(to s: NSMutableAttributedString) {
        colorize(s, pattern: #"[#;].*$"#,                                color: .systemGray, options: .anchorsMatchLines)
        colorize(s, pattern: #"^\[[^\]]+\]"#,                            color: .systemBlue, options: .anchorsMatchLines)
        colorize(s, pattern: #"^[a-zA-Z_][a-zA-Z0-9_\-\.]*\s*="#,       color: .systemTeal, options: .anchorsMatchLines)
        colorize(s, pattern: #""[^"]*""#,                                color: .systemGreen)
        colorize(s, pattern: #"'[^']*'"#,                                color: .systemGreen)
        colorize(s, pattern: #"\b(true|false)\b"#,                       color: .systemOrange)
        colorize(s, pattern: #"\b\d+\.?\d*\b"#,                          color: .systemPurple)
    }

    // MARK: - XML / HTML

    private static func applyXML(to s: NSMutableAttributedString) {
        colorize(s, pattern: #"<!--[\s\S]*?-->"#,                        color: .systemGray, options: .dotMatchesLineSeparators)
        colorize(s, pattern: #"</?[a-zA-Z][a-zA-Z0-9\-_:]*"#,           color: .systemBlue)
        colorize(s, pattern: #"[a-zA-Z\-]+="#,                           color: .systemTeal)
        colorize(s, pattern: #""[^"]*""#,                                color: .systemGreen)
        colorize(s, pattern: #"'[^']*'"#,                                color: .systemGreen)
    }

    // MARK: - 核心着色引擎

    private static func colorize(
        _ s: NSMutableAttributedString,
        pattern: String,
        color: NSColor,
        options: NSRegularExpression.Options = [],
        extra: ((_ attr: inout [NSAttributedString.Key: Any]) -> Void)? = nil
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let fullRange = NSRange(location: 0, length: s.length)
        regex.enumerateMatches(in: s.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            extra?(&attrs)
            s.addAttributes(attrs, range: range)
        }
    }
}
