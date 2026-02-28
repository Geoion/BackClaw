import AppKit
import SwiftUI

/// 高性能代码预览组件，基于 NSTextView。
/// - 支持大文件（NSTextView 增量渲染，不会一次性 layout 全部内容）
/// - 支持语法高亮（NSAttributedString）
/// - 支持文本选择、横纵滚动、等宽字体
struct CodeTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        textView.textStorage?.setAttributedString(attributedText)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // 只在内容真正变化时更新，避免重复 layout
        if textView.attributedString() != attributedText {
            textView.textStorage?.setAttributedString(attributedText)
            // 滚动回顶部
            textView.scrollToBeginningOfDocument(nil)
        }
    }
}
