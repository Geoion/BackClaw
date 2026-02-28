import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        EmptyStateView(
            title: L("No Backup Selected"),
            systemImage: "archivebox",
            description: L("Select a backup from the list to view details")
        )
    }
}
