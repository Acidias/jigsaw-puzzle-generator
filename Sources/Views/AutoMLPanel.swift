import SwiftUI

/// Main panel for configuring and running AutoML hyperparameter searches.
struct AutoMLPanel: View {
    @ObservedObject var autoMLState: AutoMLState
    @ObservedObject var modelState: ModelState
    @ObservedObject var datasetState: DatasetState
    @Binding var selection: SidebarItem?

    @State private var selectedPresetID: UUID?
    @State private var selectedDatasetID: UUID?
    @State private var studyName = ""
    @State private var numTrials = 20
    @State private var usePruning = true
    @State private var pruningStartupTrials = 5
    @State private var optimisationMetric: OptimisationMetric = .validAccuracy
    @State private var searchDimensions: [SearchDimension] = []
    @State private var trainingTarget: TrainingTarget = .local
    @State private var cloudConfig: CloudConfig = CloudConfigStore.load()
    @State private var connectionTestResult: String?
    @State private var isTestingConnection = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40))
                        .foregroundStyle(.purple)
                    Text("AutoML")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Automated hyperparameter search using Optuna")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)

                // Architecture preset picker
                presetPickerSection

                // Dataset picker
                datasetPickerSection

                // Search space editor
                if selectedPreset != nil {
                    searchSpaceSection
                }

                // Study settings
                studySettingsSection

                // Training target
                trainingTargetSection

                // Action buttons
                actionSection

                // Studies table
                if !autoMLState.studies.isEmpty {
                    studiesTableSection
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    // MARK: - Computed

    private var selectedPreset: ArchitecturePreset? {
        guard let id = selectedPresetID else { return nil }
        return modelState.presets.first { $0.id == id }
    }

    private var selectedDataset: PuzzleDataset? {
        guard let id = selectedDatasetID else { return nil }
        return datasetState.datasets.first { $0.id == id }
    }

    private var resolvedArchitecture: SiameseArchitecture? {
        guard var arch = selectedPreset?.architecture else { return nil }
        if let dataset = selectedDataset {
            let canvasSize = Int(ceil(Double(dataset.configuration.pieceSize) * 1.75))
            arch.inputSize = canvasSize
        }
        return arch
    }

    private var canRun: Bool {
        guard selectedPreset != nil && selectedDataset != nil else { return false }
        guard !studyName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !searchDimensions.isEmpty else { return false }
        guard !autoMLState.isRunning && !modelState.isTraining else { return false }
        if trainingTarget == .cloud {
            return cloudConfig.isValid
        }
        return modelState.pythonAvailable == true
    }

    // MARK: - Preset Picker

    private var presetPickerSection: some View {
        GroupBox("Architecture Preset") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Preset:", selection: $selectedPresetID) {
                    Text("Select a preset...").tag(nil as UUID?)
                    ForEach(modelState.presets) { preset in
                        Text(preset.name).tag(preset.id as UUID?)
                    }
                }

                if let preset = selectedPreset {
                    let arch = preset.architecture
                    HStack {
                        Label("\(arch.convBlocks.count) blocks", systemImage: "square.3.layers.3d")
                        Spacer()
                        Label("\(arch.embeddingDimension)-d", systemImage: "arrow.right.circle")
                        Spacer()
                        Label(arch.comparisonMethod.shortName, systemImage: "arrow.triangle.branch")
                        Spacer()
                        Label("\(arch.epochs) epochs", systemImage: "repeat")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("Non-searched parameters will use this preset's values as fixed defaults.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Dataset Picker

    private var datasetPickerSection: some View {
        GroupBox("Dataset") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Dataset:", selection: $selectedDatasetID) {
                    Text("Select a dataset...").tag(nil as UUID?)
                    ForEach(datasetState.datasets) { dataset in
                        Text("\(dataset.name) (\(dataset.totalPairs) pairs)").tag(dataset.id as UUID?)
                    }
                }

                if let dataset = selectedDataset {
                    let canvasSize = Int(ceil(Double(dataset.configuration.pieceSize) * 1.75))
                    Text("Canvas size: \(canvasSize)px (from piece size \(dataset.configuration.pieceSize)px)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Search Space

    private var searchSpaceSection: some View {
        GroupBox("Search Space") {
            VStack(alignment: .leading, spacing: 8) {
                if searchDimensions.isEmpty {
                    Text("Toggle parameters to include them in the search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(searchDimensions.count) parameter(s) will be searched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SearchSpaceEditorView(
                    dimensions: $searchDimensions,
                    baseArchitecture: resolvedArchitecture ?? SiameseArchitecture()
                )
            }
        }
    }

    // MARK: - Study Settings

    private var studySettingsSection: some View {
        GroupBox("Study Settings") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Study Name:")
                    TextField("My AutoML Study", text: $studyName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Stepper("Trials: \(numTrials)", value: $numTrials, in: 5...200, step: 5)
                }

                HStack {
                    Toggle("Pruning", isOn: $usePruning)
                        .toggleStyle(.checkbox)
                    if usePruning {
                        Stepper("Startup trials: \(pruningStartupTrials)", value: $pruningStartupTrials, in: 1...20)
                    }
                }

                Picker("Optimise:", selection: $optimisationMetric) {
                    ForEach(OptimisationMetric.allCases, id: \.self) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Training Target

    private var trainingTargetSection: some View {
        GroupBox("Training Target") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Target:", selection: $trainingTarget) {
                    ForEach(TrainingTarget.allCases, id: \.self) { target in
                        Label(target.displayName, systemImage: target.icon).tag(target)
                    }
                }
                .pickerStyle(.segmented)

                if trainingTarget == .cloud {
                    cloudConfigSection
                }

                if trainingTarget == .local {
                    if let available = modelState.pythonAvailable {
                        Label(
                            available ? "python3 found" : "python3 not found",
                            systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(available ? .green : .red)
                        .font(.caption)
                    }
                }
            }
        }
        .task {
            if modelState.pythonAvailable == nil {
                modelState.pythonAvailable = await TrainingRunner.isPythonAvailable()
            }
        }
    }

    private var cloudConfigSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hostname:")
                    .frame(width: 80, alignment: .trailing)
                TextField("gpu-instance.example.com", text: $cloudConfig.hostname)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Username:")
                    .frame(width: 80, alignment: .trailing)
                TextField("root", text: $cloudConfig.username)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Port:")
                    .frame(width: 80, alignment: .trailing)
                TextField("22", value: $cloudConfig.port, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            HStack {
                Text("SSH Key:")
                    .frame(width: 80, alignment: .trailing)
                TextField("~/.ssh/id_rsa", text: $cloudConfig.sshKeyPath)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Remote Dir:")
                    .frame(width: 80, alignment: .trailing)
                TextField("/workspace/training", text: $cloudConfig.remoteWorkDir)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Test Connection") {
                    isTestingConnection = true
                    connectionTestResult = nil
                    Task {
                        let (success, message) = await CloudTrainingRunner.testConnection(config: cloudConfig)
                        connectionTestResult = success ? "Connected" : message
                        isTestingConnection = false
                        CloudConfigStore.save(cloudConfig)
                    }
                }
                .disabled(isTestingConnection || cloudConfig.hostname.isEmpty)

                if isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }
                if let result = connectionTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result == "Connected" ? .green : .red)
                }
            }
        }
        .font(.callout)
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button {
                createAndRunStudy()
            } label: {
                Label("Create & Run Study", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(!canRun)

            // Validation feedback
            if autoMLState.isRunning {
                Label("Another AutoML study is running", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if modelState.isTraining {
                Label("Model training is in progress", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if searchDimensions.isEmpty && selectedPreset != nil {
                Label("Select at least one parameter to search", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Studies Table

    private var studiesTableSection: some View {
        GroupBox("Studies") {
            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack(spacing: 0) {
                    Text("Name")
                        .frame(width: 150, alignment: .leading)
                    Text("Status")
                        .frame(width: 80, alignment: .leading)
                    Text("Trials")
                        .frame(width: 60, alignment: .trailing)
                    Text("Best Value")
                        .frame(width: 80, alignment: .trailing)
                    Text("Dataset")
                        .frame(width: 120, alignment: .leading)
                    Text("Date")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                ForEach(autoMLState.studies.sorted(by: { $0.createdAt > $1.createdAt })) { study in
                    Button {
                        selection = .study(study.id)
                    } label: {
                        HStack(spacing: 0) {
                            Text(study.name)
                                .lineLimit(1)
                                .frame(width: 150, alignment: .leading)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(studyStatusColour(study.status))
                                    .frame(width: 8, height: 8)
                                Text(study.status.rawValue)
                            }
                            .frame(width: 80, alignment: .leading)

                            Text("\(study.completedTrials)/\(study.configuration.numTrials)")
                                .frame(width: 60, alignment: .trailing)

                            if let bestNum = study.bestTrialNumber,
                               let bestTrial = study.trials.first(where: { $0.trialNumber == bestNum }) {
                                Text(bestTrial.value.map { String(format: "%.4f", $0) } ?? "-")
                                    .frame(width: 80, alignment: .trailing)
                            } else {
                                Text("-")
                                    .frame(width: 80, alignment: .trailing)
                            }

                            Text(study.sourceDatasetName)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)

                            Text(study.createdAt, style: .date)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - Actions

    private func createAndRunStudy() {
        guard let arch = resolvedArchitecture,
              let dataset = selectedDataset,
              let preset = selectedPreset else { return }

        let config = AutoMLConfiguration(
            baseArchitecture: arch,
            dimensions: searchDimensions,
            numTrials: numTrials,
            usePruning: usePruning,
            pruningStartupTrials: pruningStartupTrials,
            optimisationMetric: optimisationMetric
        )

        let study = AutoMLStudy(
            name: studyName.trimmingCharacters(in: .whitespaces),
            sourceDatasetID: dataset.id,
            sourceDatasetName: dataset.name,
            sourcePresetName: preset.name,
            configuration: config
        )

        autoMLState.addStudy(study)
        selection = .study(study.id)

        // Start training
        Task {
            if trainingTarget == .cloud {
                CloudConfigStore.save(cloudConfig)
                await AutoMLRunner.trainCloud(
                    study: study,
                    dataset: dataset,
                    config: cloudConfig,
                    state: autoMLState,
                    modelState: modelState
                )
            } else {
                await AutoMLRunner.train(
                    study: study,
                    dataset: dataset,
                    state: autoMLState,
                    modelState: modelState
                )
            }
        }
    }

    private func studyStatusColour(_ status: StudyStatus) -> Color {
        switch status {
        case .configured: return .blue
        case .running: return .orange
        case .completed: return .green
        case .cancelled: return .yellow
        case .failed: return .red
        }
    }
}
