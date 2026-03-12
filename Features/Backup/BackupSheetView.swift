import AppKit
import SwiftUI

private enum BackupWizardStep: Hashable {
    case assistant
    case mode
    case selection
    case naming
    case result

    var titleKey: String {
        switch self {
        case .assistant:
            return "Backup Step Assistant"
        case .mode:
            return "Backup Step Mode"
        case .selection:
            return "Backup Step Selection"
        case .naming:
            return "Backup Step Naming"
        case .result:
            return "Backup Step Result"
        }
    }
}

struct BackupSheetView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @Binding var isPresented: Bool

    @State private var currentStep: BackupWizardStep = .assistant
    @State private var selectedAssistantProduct: BackupAssistantProduct = .openclaw
    @State private var contentMode: BackupContentMode = .all

    @State private var useCustomState = false
    @State private var customStatePath: String = UserDefaults.standard.string(forKey: "lastCustomStatePath") ?? ""
    @State private var includeCustomWorkspaces = false
    @State private var workspacePaths: [WorkspacePath] = []
    @State private var essentialsSourceSelections: [EssentialsSourceSelection] = []

    @State private var addingPath: String = ""
    @State private var customLabel: String = ""

    @State private var estimatePhase: EstimatePhase = .idle
    @State private var estimateTask: Task<Void, Never>?
    @State private var phase: BackupPhase = .idle

    private var stateURL: URL {
        if useCustomState, !customStatePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: customStatePath, isDirectory: true)
        }
        return OpenClawPaths.stateDirectory
    }

    private var flowSteps: [BackupWizardStep] {
        if contentMode == .essentials {
            return [.assistant, .mode, .selection, .naming, .result]
        }
        return [.assistant, .mode, .naming, .result]
    }

    private var currentStepIndex: Int {
        flowSteps.firstIndex(of: currentStep) ?? 0
    }

    private var canGoBack: Bool {
        currentStep != .assistant && currentStep != .result && phase != .running
    }

    private var canContinue: Bool {
        switch currentStep {
        case .assistant:
            return true
        case .mode:
            return hasValidStateDirectory
        case .selection:
            return hasValidStateDirectory
        case .naming:
            return hasValidStateDirectory
        case .result:
            return false
        }
    }

    private var hasValidStateDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: stateURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private var selectedWorkspaceURLs: [URL] {
        guard includeCustomWorkspaces else { return [] }
        return workspacePaths
            .filter(\.isSelected)
            .map { $0.url.standardizedFileURL }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(currentStep == .result ? L("Backup Result") : L("Backup Wizard Title"))
                .font(.title2)
                .bold()
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

            stepProgressBar
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch currentStep {
                    case .assistant:
                        assistantStep
                    case .mode:
                        modeStep
                    case .selection:
                        selectionStep
                    case .naming:
                        namingStep
                    case .result:
                        resultStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            actionBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 560, idealHeight: 760)
        .onAppear {
            reloadDataFromPaths()
            synchronizeStepWithFlow()
            scheduleEstimateCalculation()
        }
        .onDisappear {
            estimateTask?.cancel()
        }
        .onChange(of: useCustomState) { _, _ in
            reloadDataFromPaths()
            scheduleEstimateCalculation()
        }
        .onChange(of: customStatePath) { _, _ in
            guard useCustomState else { return }
            reloadDataFromPaths()
            scheduleEstimateCalculation()
        }
        .onChange(of: includeCustomWorkspaces) { _, _ in
            reloadEssentialsSourceSelections()
            scheduleEstimateCalculation()
        }
        .onChange(of: workspacePaths) { _, _ in
            reloadEssentialsSourceSelections()
            scheduleEstimateCalculation()
        }
        .onChange(of: contentMode) { _, _ in
            synchronizeStepWithFlow()
            scheduleEstimateCalculation()
        }
        .onChange(of: essentialsSourceSelections) { _, _ in
            scheduleEstimateCalculation()
        }
    }

    // MARK: - Steps

    private var assistantStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Step Assistant Description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: $selectedAssistantProduct) {
                ForEach(BackupAssistantProduct.allCases, id: \.self) { product in
                    Text(L(product.titleKey)).tag(product)
                }
            }
            .pickerStyle(.segmented)
            .disabled(phase == .running)

            Text(L("Assistant Product Note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionBlock(
                title: L("State Directory"),
                footnote: L("Contains configs, credentials, sessions and all agent data.")
            ) {
                if !useCustomState {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                        Text(OpenClawPaths.stateDirectory.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(L("Customize")) { useCustomState = true }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    HStack(spacing: 6) {
                        TextField(L("State Directory Path"), text: $customStatePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .disabled(phase == .running)
                        Button(L("Choose...")) { chooseDirectory(for: .state) }
                            .disabled(phase == .running)
                        Button(L("Reset")) {
                            useCustomState = false
                            customStatePath = ""
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                if !hasValidStateDirectory {
                    Text(L("State Directory Invalid"))
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            SectionBlock(
                title: L("Custom Workspace Paths"),
                footnote: L("By default, only state is backed up (workspace under state is already included).")
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L("Include custom workspace paths"), isOn: $includeCustomWorkspaces)
                        .font(.subheadline)
                        .disabled(phase == .running)

                    if includeCustomWorkspaces {
                        if workspacePaths.isEmpty {
                            Text(L("No custom workspace path discovered yet."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(workspacePaths.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 8) {
                                Toggle("", isOn: $workspacePaths[index].isSelected)
                                    .labelsHidden()
                                    .disabled(phase == .running)
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                                Text(item.url.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    workspacePaths.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(phase == .running)
                            }
                        }

                        HStack(spacing: 6) {
                            TextField(L("Add Workspace Path..."), text: $addingPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .disabled(phase == .running)
                            Button(L("Browse...")) { chooseDirectory(for: .workspace) }
                                .disabled(phase == .running)
                            Button(L("Add")) { commitAddingPath() }
                                .disabled(addingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .running)
                        }

                        Text(L("Only checked paths will be included in this backup."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SectionBlock(
                title: L("Backup Mode"),
                footnote: contentMode == .all
                    ? L("Full backup includes all files from selected sources.")
                    : L("Partial backup includes required paths plus selected optional top-level directories.")
            ) {
                Picker("", selection: $contentMode) {
                    Text(L("Backup All")).tag(BackupContentMode.all)
                    Text(L("Backup Essentials")).tag(BackupContentMode.essentials)
                }
                .pickerStyle(.segmented)
                .disabled(phase == .running)
            }
        }
    }

    private var selectionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Step Selection Description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if essentialsSourceSelections.isEmpty {
                Text(L("No source available for partial selection."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(Array(essentialsSourceSelections.enumerated()), id: \.element.id) { sourceIndex, source in
                    SourceEssentialsCard(
                        title: source.title,
                        subtitle: source.path,
                        requiredItems: source.requiredItems,
                        optionalDirectories: source.optionalDirectories,
                        disabled: phase == .running
                    ) { directoryID in
                        if let dirIndex = essentialsSourceSelections[sourceIndex]
                            .optionalDirectories
                            .firstIndex(where: { $0.id == directoryID }) {
                            essentialsSourceSelections[sourceIndex].optionalDirectories[dirIndex].isSelected.toggle()
                        }
                    }
                }
            }

            estimateCard
        }
    }

    private var namingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Step Naming Description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SectionBlock(
                title: L("Backup Label (Optional)"),
                footnote: L("Appended to archive ID. Letters, numbers, hyphens only.")
            ) {
                TextField(L("e.g. upgrade-before-v2"), text: $customLabel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(phase == .running)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("Backup Summary"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text(L("Assistant Product")).foregroundStyle(.secondary)
                        Text(L(selectedAssistantProduct.titleKey))
                    }
                    GridRow {
                        Text(L("Backup Mode")).foregroundStyle(.secondary)
                        Text(contentMode == .all ? L("Backup All") : L("Backup Essentials"))
                    }
                    GridRow {
                        Text(L("Total Sources")).foregroundStyle(.secondary)
                        Text("\(1 + selectedWorkspaceURLs.count)")
                    }
                }
                .font(.caption)
            }

            estimateCard
        }
    }

    @ViewBuilder
    private var resultStep: some View {
        switch phase {
        case .idle:
            Text(L("No backup started yet."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Backing up, please wait..."))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

        case .success(let result):
            VStack(alignment: .leading, spacing: 8) {
                Label(L("Backup Succeeded"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.green)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text(L("Assistant Product")).foregroundStyle(.secondary)
                        Text(L(result.meta.assistantProduct.titleKey))
                    }
                    GridRow {
                        Text(L("OpenClaw Version")).foregroundStyle(.secondary)
                        Text(result.meta.openClawVersion).font(.system(.caption, design: .monospaced))
                    }
                    GridRow {
                        Text(L("File Count")).foregroundStyle(.secondary)
                        Text("\(result.meta.fileCount) \(L("files"))")
                    }
                    GridRow {
                        Text(L("Backup Size")).foregroundStyle(.secondary)
                        Text(Formatters.byteCount(result.meta.sizeBytes))
                    }
                    GridRow {
                        Text(L("Elapsed")).foregroundStyle(.secondary)
                        Text(String(format: "%.2f \(L("seconds"))", result.elapsed))
                    }
                    GridRow {
                        Text(L("Archive ID")).foregroundStyle(.secondary)
                        Text(result.meta.archiveId).font(.system(.caption, design: .monospaced))
                    }
                }
                .font(.caption)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.green.opacity(0.2), lineWidth: 1))

        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(L("Backup Failed"), systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.2), lineWidth: 1))
        }
    }

    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Live Estimate"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            switch estimatePhase {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Estimating backup size and file count..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .ready(let estimate):
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text(L("Estimated Files")).foregroundStyle(.secondary)
                        Text("\(estimate.fileCount) \(L("files"))")
                    }
                    GridRow {
                        Text(L("Estimated Size")).foregroundStyle(.secondary)
                        Text(Formatters.byteCount(estimate.sizeBytes))
                    }
                }
                .font(.caption)
            case .failure(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Estimate Failed"))
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Progress + Actions

    private var stepProgressBar: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(flowSteps.enumerated()), id: \.element) { index, step in
                WizardStepBadge(
                    title: L(step.titleKey),
                    index: index + 1,
                    state: badgeState(for: index)
                )
                .frame(width: 86)

                if index < flowSteps.count - 1 {
                    Rectangle()
                        .fill(index < currentStepIndex ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.25))
                        .frame(height: 2)
                        .padding(.top, 13)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if currentStep == .result {
                Button(L("Close")) { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(phase == .running)

                Spacer()

                if phase != .running {
                    Button(L("New Backup")) {
                        resetWizard()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button(L("Cancel")) { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(phase == .running)

                if canGoBack {
                    Button(L("Back")) {
                        goBackStep()
                    }
                    .buttonStyle(.bordered)
                    .disabled(phase == .running)
                }

                Spacer()

                Button {
                    proceedStep()
                } label: {
                    Text(currentStep == .naming ? L("Start Backup Now") : L("Next"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue || phase == .running)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    // MARK: - Actions

    private func badgeState(for index: Int) -> WizardStepBadge.State {
        if index < currentStepIndex { return .done }
        if index == currentStepIndex { return .active }
        return .pending
    }

    private func proceedStep() {
        if currentStep == .naming {
            currentStep = .result
            runBackup()
            return
        }

        let nextIndex = currentStepIndex + 1
        guard nextIndex < flowSteps.count else { return }
        currentStep = flowSteps[nextIndex]
    }

    private func goBackStep() {
        let previousIndex = currentStepIndex - 1
        guard previousIndex >= 0, previousIndex < flowSteps.count else { return }
        currentStep = flowSteps[previousIndex]
    }

    private func resetWizard() {
        phase = .idle
        currentStep = .assistant
        customLabel = ""
        scheduleEstimateCalculation()
    }

    private func synchronizeStepWithFlow() {
        if !flowSteps.contains(currentStep) {
            currentStep = .naming
        }
    }

    private func reloadDataFromPaths() {
        loadWorkspaces()
        reloadEssentialsSourceSelections()
    }

    private func loadWorkspaces() {
        let discovered = OpenClawPaths
            .discoverWorkspacesOutsideState(stateURL: stateURL)
            .map { $0.url.standardizedFileURL }

        let previousSelectionByPath = Dictionary(uniqueKeysWithValues: workspacePaths.map { ($0.normalizedPath, $0.isSelected) })
        let discoveredPathSet = Set(discovered.map(\.path))

        var merged: [WorkspacePath] = discovered.map { url in
            WorkspacePath(url: url, isSelected: previousSelectionByPath[url.path] ?? false)
        }

        let manualPaths = workspacePaths.filter { !discoveredPathSet.contains($0.normalizedPath) }
        merged.append(contentsOf: manualPaths)

        var seen: Set<String> = []
        workspacePaths = merged
            .filter { seen.insert($0.normalizedPath).inserted }
            .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    private func reloadEssentialsSourceSelections() {
        let previousSelection = Dictionary(uniqueKeysWithValues: essentialsSourceSelections.map { source in
            (
                source.sourceKey,
                Set(source.optionalDirectories.filter(\.isSelected).map(\.normalizedName))
            )
        })

        let sources = buildActiveSources()
        essentialsSourceSelections = sources.map { source in
            let optionalNames = BackupEssentials.optionalTopLevelDirectoryNames(
                in: source.url,
                sourceKind: source.kind
            )
            let selectedNames = previousSelection[source.sourceKey] ?? []
            let optionalDirectories = optionalNames.map { name in
                OptionalDirectorySelection(name: name, isSelected: selectedNames.contains(name.lowercased()))
            }
            return EssentialsSourceSelection(
                sourceKey: source.sourceKey,
                title: source.title,
                path: source.url.path,
                requiredItems: BackupEssentials.requiredDisplayItems(for: source.kind),
                optionalDirectories: optionalDirectories
            )
        }
    }

    private func buildActiveSources() -> [BackupSourceDraft] {
        var result: [BackupSourceDraft] = [
            BackupSourceDraft(
                sourceKey: stateURL.standardizedFileURL.path,
                title: "STATE",
                kind: .state,
                url: stateURL.standardizedFileURL
            )
        ]

        if includeCustomWorkspaces {
            let sorted = selectedWorkspaceURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            for workspaceURL in sorted {
                let title = "WORKSPACE: \(workspaceURL.lastPathComponent)"
                result.append(BackupSourceDraft(
                    sourceKey: workspaceURL.path,
                    title: title,
                    kind: .workspace,
                    url: workspaceURL
                ))
            }
        }

        return result
    }

    private func commitAddingPath() {
        let path = addingPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL

        if let index = workspacePaths.firstIndex(where: { $0.normalizedPath == url.path }) {
            workspacePaths[index].isSelected = true
        } else {
            workspacePaths.append(WorkspacePath(url: url, isSelected: true))
        }

        addingPath = ""
    }

    private func chooseDirectory(for target: DirectoryTarget) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Select")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch target {
        case .state:
            customStatePath = url.path
            UserDefaults.standard.set(url.path, forKey: "lastCustomStatePath")
        case .workspace:
            addingPath = url.path
        }
    }

    private func backupRequest(label: String?) -> BackupRequest {
        var optionalSelectionsBySourcePath: [String: Set<String>] = [:]
        if contentMode == .essentials {
            for source in essentialsSourceSelections {
                optionalSelectionsBySourcePath[source.sourceKey] = Set(
                    source.optionalDirectories
                        .filter(\.isSelected)
                        .map(\.normalizedName)
                )
            }
        }

        return BackupRequest(
            stateURL: stateURL.standardizedFileURL,
            workspaceURLs: selectedWorkspaceURLs,
            assistantProduct: selectedAssistantProduct,
            contentMode: contentMode,
            optionalTopLevelSelectionsBySourcePath: optionalSelectionsBySourcePath,
            label: label
        )
    }

    private func scheduleEstimateCalculation() {
        estimateTask?.cancel()
        let request = backupRequest(label: nil)
        estimatePhase = .loading

        estimateTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            if Task.isCancelled { return }

            let service = LocalBackupService()
            do {
                let estimate = try await Task.detached(priority: .utility) {
                    try service.estimateBackupMetrics(request: request)
                }.value
                if Task.isCancelled { return }
                await MainActor.run {
                    estimatePhase = .ready(estimate)
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    estimatePhase = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func runBackup() {
        phase = .running
        let request = backupRequest(label: customLabel.isEmpty ? nil : customLabel)

        Task {
            do {
                let service = LocalBackupService()
                let result = try await Task.detached(priority: .userInitiated) {
                    try service.createManualBackup(request: request)
                }.value
                archiveStore.refresh()
                phase = .success(result)
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }

    private enum DirectoryTarget { case state, workspace }
}

private enum EstimatePhase: Equatable {
    case idle
    case loading
    case ready(BackupEstimate)
    case failure(String)

    static func == (lhs: EstimatePhase, rhs: EstimatePhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading):
            return true
        case (.ready(let l), .ready(let r)):
            return l == r
        case (.failure(let l), .failure(let r)):
            return l == r
        default:
            return false
        }
    }
}

private struct WizardStepBadge: View {
    enum State {
        case pending
        case active
        case done
    }

    let title: String
    let index: Int
    let state: State

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 28, height: 28)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(textColor)
                }
            }
            Text(title)
                .font(.caption)
                .fontWeight(state == .active ? .semibold : .regular)
                .foregroundStyle(state == .pending ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var circleColor: Color {
        switch state {
        case .pending:
            return Color.secondary.opacity(0.2)
        case .active:
            return Color.accentColor.opacity(0.18)
        case .done:
            return Color.accentColor
        }
    }

    private var textColor: Color {
        switch state {
        case .pending:
            return .secondary
        case .active:
            return .accentColor
        case .done:
            return .white
        }
    }
}

private struct SectionBlock<Content: View>: View {
    let title: String
    let footnote: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct SourceEssentialsCard: View {
    let title: String
    let subtitle: String
    let requiredItems: [String]
    let optionalDirectories: [OptionalDirectorySelection]
    let disabled: Bool
    let onToggleOptional: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(L("Core Required Directories"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading),
                    GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading),
                    GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(requiredItems, id: \.self) { item in
                    RequiredItemChip(label: item)
                }
            }

            Text(L("Optional Directories"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if optionalDirectories.isEmpty {
                Text(L("No optional directories found under current source path."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading),
                        GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading),
                        GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(optionalDirectories) { item in
                        OptionalDirectoryChip(
                            name: item.name,
                            isSelected: item.isSelected,
                            disabled: disabled
                        ) {
                            onToggleOptional(item.id)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RequiredItemChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .imageScale(.small)
                .foregroundStyle(.green)
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(L("Required"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct OptionalDirectoryChip: View {
    let name: String
    let isSelected: Bool
    let disabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.small)
                Text(name)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct BackupSourceDraft {
    let sourceKey: String
    let title: String
    let kind: BackupSourceKind
    let url: URL
}

private struct EssentialsSourceSelection: Identifiable, Equatable {
    var id: String { sourceKey }
    let sourceKey: String
    let title: String
    let path: String
    let requiredItems: [String]
    var optionalDirectories: [OptionalDirectorySelection]
}

private struct WorkspacePath: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var isSelected: Bool

    init(id: UUID = UUID(), url: URL, isSelected: Bool) {
        self.id = id
        self.url = url
        self.isSelected = isSelected
    }

    var normalizedPath: String { url.standardizedFileURL.path }
}

private struct OptionalDirectorySelection: Identifiable, Equatable {
    let id: UUID
    let name: String
    var isSelected: Bool

    init(id: UUID = UUID(), name: String, isSelected: Bool) {
        self.id = id
        self.name = name
        self.isSelected = isSelected
    }

    var normalizedName: String { name.lowercased() }
}

private enum BackupPhase: Equatable {
    case idle
    case running
    case success(BackupOperationResult)
    case failure(String)

    static func == (lhs: BackupPhase, rhs: BackupPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.running, .running):
            return true
        case (.success(let l), .success(let r)):
            return l.meta.archiveId == r.meta.archiveId
        case (.failure(let a), .failure(let b)):
            return a == b
        default:
            return false
        }
    }
}
