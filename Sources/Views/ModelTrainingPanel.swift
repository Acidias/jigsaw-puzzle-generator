import SwiftUI

/// Main panel for creating Siamese Neural Network models from presets.
struct ModelTrainingPanel: View {
    @ObservedObject var modelState: ModelState
    @ObservedObject var datasetState: DatasetState
    @Binding var selection: SidebarItem?

    @State private var selectedPresetID: UUID?
    @State private var selectedDatasetID: UUID?
    @State private var modelName = ""
    @State private var connectionTestResult: String?
    @State private var isTestingConnection = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundStyle(.indigo)
                    Text("Model Training")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Pick an architecture preset and dataset, then create and train a model")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)

                // Architecture preset picker
                presetPickerSection

                // Dataset picker
                datasetPickerSection

                // Training target
                trainingTargetSection

                // Action buttons
                actionSection

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

    /// Build the architecture from the selected preset, overriding inputSize from the dataset.
    private var resolvedArchitecture: SiameseArchitecture? {
        guard var arch = selectedPreset?.architecture else { return nil }
        if let dataset = selectedDataset {
            let canvasSize = Int(ceil(Double(dataset.configuration.pieceSize) * 1.75))
            arch.inputSize = canvasSize
        }
        return arch
    }

    private var canCreate: Bool {
        selectedPreset != nil && selectedDataset != nil && !modelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canTrain: Bool {
        guard canCreate && !modelState.isTraining else { return false }
        if modelState.trainingTarget == .cloud {
            return modelState.cloudConfig.isValid
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
                .font(.callout)

                if modelState.presets.isEmpty {
                    Text("No presets available. Create one in Architecture Presets.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let preset = selectedPreset {
                    architectureSummary(preset.architecture)
                }
            }
            .padding(8)
        }
    }

    private func architectureSummary(_ arch: SiameseArchitecture) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let filters = arch.convBlocks.map { String($0.filters) }.joined(separator: " > ")
            summaryRow("Conv blocks", "\(arch.convBlocks.count) (\(filters))")
            summaryRow("Embedding", "\(arch.embeddingDimension)-d")
            summaryRow("Comparison", arch.comparisonMethod.displayName)
            summaryRow("Dropout", String(format: "%.2f", arch.dropout))
            Divider()
            summaryRow("Learning rate", "\(arch.learningRate)")
            summaryRow("Batch size", "\(arch.batchSize)")
            summaryRow("Epochs", "\(arch.epochs)")
            if let dataset = selectedDataset {
                let canvasSize = Int(ceil(Double(dataset.configuration.pieceSize) * 1.75))
                Divider()
                summaryRow("Input size", "\(canvasSize) x \(canvasSize) (from dataset)")
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
    }

    // MARK: - Dataset Picker

    private var datasetPickerSection: some View {
        GroupBox("Source Dataset") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Dataset:", selection: $selectedDatasetID) {
                    Text("Select a dataset...").tag(nil as UUID?)
                    ForEach(datasetState.datasets) { dataset in
                        Text("\(dataset.name) (\(dataset.totalPairs) pairs)")
                            .tag(dataset.id as UUID?)
                    }
                }
                .font(.callout)

                if datasetState.datasets.isEmpty {
                    Text("No datasets available. Generate a dataset first.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let dataset = selectedDataset {
                    let canvasSize = Int(ceil(Double(dataset.configuration.pieceSize) * 1.75))
                    Text("Canvas size: \(canvasSize)x\(canvasSize) px - Input will be set to \(canvasSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Model name:")
                        .font(.callout)
                    TextField("My Siamese Model", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Training Target

    private var trainingTargetSection: some View {
        GroupBox("Training Target") {
            VStack(spacing: 8) {
                Picker("Target:", selection: $modelState.trainingTarget) {
                    ForEach(TrainingTarget.allCases, id: \.rawValue) { target in
                        Label(target.displayName, systemImage: target.icon).tag(target)
                    }
                }
                .pickerStyle(.segmented)

                if modelState.trainingTarget == .cloud {
                    panelCloudConfigForm
                }
            }
            .padding(8)
        }
    }

    private var panelCloudConfigForm: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Host:")
                    .font(.callout)
                    .frame(width: 60, alignment: .trailing)
                TextField("192.168.1.100 or hostname", text: $modelState.cloudConfig.hostname)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: modelState.cloudConfig.hostname) { _, _ in
                        CloudConfigStore.save(modelState.cloudConfig)
                        connectionTestResult = nil
                    }
            }
            HStack {
                Text("User:")
                    .font(.callout)
                    .frame(width: 60, alignment: .trailing)
                TextField("root", text: $modelState.cloudConfig.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150)
                    .onChange(of: modelState.cloudConfig.username) { _, _ in
                        CloudConfigStore.save(modelState.cloudConfig)
                    }
                Text("Port:")
                    .font(.callout)
                TextField("22", value: $modelState.cloudConfig.port, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onChange(of: modelState.cloudConfig.port) { _, _ in
                        CloudConfigStore.save(modelState.cloudConfig)
                    }
            }
            HStack {
                Text("Key:")
                    .font(.callout)
                    .frame(width: 60, alignment: .trailing)
                TextField("~/.ssh/id_rsa", text: $modelState.cloudConfig.sshKeyPath)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: modelState.cloudConfig.sshKeyPath) { _, _ in
                        CloudConfigStore.save(modelState.cloudConfig)
                        connectionTestResult = nil
                    }
                Button("Browse...") {
                    browseSSHKey()
                }
                .controlSize(.small)
            }
            HStack {
                Text("Dir:")
                    .font(.callout)
                    .frame(width: 60, alignment: .trailing)
                TextField("/workspace/training", text: $modelState.cloudConfig.remoteWorkDir)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: modelState.cloudConfig.remoteWorkDir) { _, _ in
                        CloudConfigStore.save(modelState.cloudConfig)
                    }
            }

            HStack {
                Button {
                    testConnection()
                } label: {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTestingConnection || !modelState.cloudConfig.isValid)

                if isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }

                if let result = connectionTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("successful") ? .green : .red)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func browseSSHKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSString(string: "~/.ssh").expandingTildeInPath)
        panel.message = "Select your SSH private key"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        modelState.cloudConfig.sshKeyPath = url.path
        CloudConfigStore.save(modelState.cloudConfig)
        connectionTestResult = nil
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        let config = modelState.cloudConfig
        Task {
            let (success, message) = await CloudTrainingRunner.testConnection(config: config)
            await MainActor.run {
                connectionTestResult = message
                isTestingConnection = false
                _ = success
            }
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    createModel(andTrain: false)
                } label: {
                    Label("Create Model", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCreate)

                Button {
                    createModel(andTrain: true)
                } label: {
                    Label("Create & Train", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.green)
                .disabled(!canTrain)
            }

            if !canCreate {
                if selectedPreset == nil {
                    Text("Select an architecture preset to continue")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if selectedDataset == nil {
                    Text("Select a source dataset to continue")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if modelName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Enter a model name to continue")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if modelState.trainingTarget == .local && modelState.pythonAvailable == false {
                Label("python3 not found - install Python to enable in-app training", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if modelState.trainingTarget == .cloud && !modelState.cloudConfig.isValid {
                Label("Configure SSH connection above to enable cloud training", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task {
            if modelState.pythonAvailable == nil {
                modelState.pythonAvailable = await TrainingRunner.isPythonAvailable()
            }
        }
    }

    // MARK: - Actions

    private func createModel(andTrain: Bool) {
        guard let architecture = resolvedArchitecture,
              let dataset = selectedDataset else { return }
        let name = modelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let model = SiameseModel(
            name: name,
            sourceDatasetID: dataset.id,
            sourceDatasetName: dataset.name,
            architecture: architecture
        )
        modelState.addModel(model)

        if andTrain {
            // Navigate to the model detail view, then start training
            selection = .model(model.id)
            Task {
                if modelState.trainingTarget == .cloud {
                    await CloudTrainingRunner.train(
                        model: model, dataset: dataset,
                        config: modelState.cloudConfig, state: modelState
                    )
                } else {
                    await TrainingRunner.train(model: model, dataset: dataset, state: modelState)
                }
            }
        }
    }
}
