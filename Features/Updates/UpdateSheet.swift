import AppKit
import SwiftUI

struct UpdateSheet: View {
    let release: AppRelease
    @Binding var isPresented: Bool

    private var currentVersion: String { AppPaths.appVersion }

    private var markdownBody: AttributedString {
        (try? AttributedString(markdown: release.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(release.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header

            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Update Available"))
                        .font(.title2).bold()
                    Text(release.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            // MARK: Content

            VStack(alignment: .leading, spacing: 18) {

                // Version comparison row
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Current Version"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currentVersion)
                            .font(.system(.body, design: .monospaced))
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("New Version"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(release.version)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.blue)
                    }

                    Spacer()
                }

                // Release notes
                if !release.body.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Release Notes"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(markdownBody)
                                .font(.system(.caption))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        .frame(height: 140)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 18)

            Divider()

            // MARK: Buttons

            HStack {
                Button(L("Later")) {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(L("Download")) {
                    NSWorkspace.shared.open(release.htmlURL)
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 480)
    }
}
