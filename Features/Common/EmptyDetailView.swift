import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        EmptyStateView(
            title: "未选择备份",
            systemImage: "archivebox",
            description: "从左侧列表选择一个备份以查看详情"
        )
    }
}
