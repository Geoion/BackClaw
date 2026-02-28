import AppKit
import SwiftUI

struct ExportSheetView: View {
    let archive: BackupArchive
    @Binding var isPresented: Bool

    @State private var format: ExportFormat = .tarGz
    @State private var compressionLevel: CompressionLevel = .standard
    @State private var phase: ExportPhase = .idle

    private let service = ExportService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(L("Export Archive"))
                .font(.title2).bold()
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()

            VStack(alignment: .leading, spacing: 18) {

                SectionBlock(title: L("Archive")) {
                    HStack(spacing: 8) {
                        Image(systemName: "archivebox")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(archive.meta.archiveId)
                                .font(.system(.subheadline, design: .monospaced))
                            Text("\(archive.meta.fileCount) \(L("files")) · \(Formatters.byteCount(archive.meta.sizeBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SectionBlock(title: L("Format")) {
                    HStack(spacing: 10) {
                        ForEach(ExportFormat.allCases) { fmt in
                            FormatButton(
                                format: fmt,
                                isSelected: format == fmt,
                                isDisabled: phase == .exporting
                            ) { format = fmt }
                        }
                        Spacer()
                    }
                }

                SectionBlock(title: L("Compression Level")) {
                    Picker("", selection: $compressionLevel) {
                        ForEach(CompressionLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(phase == .exporting)
                }

                if phase != .idle {
                    phaseView
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Spacer(minLength: 0)
            Divider()

            HStack {
                Spacer()
                Button(L("Cancel")) { isPresented = false }
                    .disabled(phase == .exporting)
                    .keyboardShortcut(.escape, modifiers: [])

                Button {
                    runExport()
                } label: {
                    if phase == .exporting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L("Exporting..."))
                        }
                    } else {
                        Label(L("Choose Location & Export"), systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(phase == .exporting)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 结果视图

    @ViewBuilder
    private var phaseView: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .exporting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Compressing, please wait...")).foregroundStyle(.secondary).font(.subheadline)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

        case .success(let result):
            VStack(alignment: .leading, spacing: 10) {
                Label(L("Export Succeeded"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline).bold().foregroundStyle(.green)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text(L("File Size")).foregroundStyle(.secondary)
                        Text(Formatters.byteCount(result.sizeBytes))
                    }
                    GridRow {
                        Text(L("Elapsed")).foregroundStyle(.secondary)
                        Text(String(format: "%.2f \(L("seconds"))", result.elapsed))
                    }
                    GridRow {
                        Text(L("Output Path")).foregroundStyle(.secondary)
                        Text(result.outputURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                } label: {
                    Label(L("Show in Finder"), systemImage: "folder")
                }
                .buttonStyle(.link)
                .font(.subheadline)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.green.opacity(0.2), lineWidth: 1))

        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(L("Export Failed"), systemImage: "xmark.circle.fill")
                    .font(.subheadline).bold().foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func runExport() {
        let panel = NSSavePanel()
        panel.title = L("Choose Export Location")
        panel.nameFieldStringValue = "\(archive.meta.archiveId).\(format.fileExtension)"
        panel.allowedContentTypes = format == .zip ? [.zip] : []
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let outputDir = outputURL.deletingLastPathComponent()
        let request = ExportRequest(
            archive: archive,
            format: format,
            compressionLevel: compressionLevel,
            outputDirectory: outputDir
        )

        let finalOutputURL = outputURL
        phase = .exporting

        Task {
            do {
                var result = try await service.export(request: request)
                if result.outputURL != finalOutputURL {
                    try? FileManager.default.moveItem(at: result.outputURL, to: finalOutputURL)
                    let attrs = try? FileManager.default.attributesOfItem(atPath: finalOutputURL.path)
                    let size = attrs?[.size] as? Int64 ?? result.sizeBytes
                    result = ExportResult(outputURL: finalOutputURL, sizeBytes: size, elapsed: result.elapsed)
                }
                phase = .success(result)
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }
}

// MARK: - 格式按钮

private struct FormatButton: View {
    let format: ExportFormat
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: format.systemImage)
                    .imageScale(.small)
                Text(format.displayName)
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.accentColor : Color(NSColor.controlColor),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - SectionBlock

private struct SectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - Phase

private enum ExportPhase: Equatable {
    case idle
    case exporting
    case success(ExportResult)
    case failure(String)

    static func == (lhs: ExportPhase, rhs: ExportPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.exporting, .exporting): return true
        case (.success, .success): return true
        case (.failure(let a), .failure(let b)): return a == b
        default: return false
        }
    }
}
