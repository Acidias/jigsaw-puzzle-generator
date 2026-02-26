import SwiftUI

/// Main panel for designing and creating Siamese Neural Network models.
struct ModelTrainingPanel: View {
    @ObservedObject var modelState: ModelState
    @ObservedObject var datasetState: DatasetState
    @Binding var selection: SidebarItem?

    @State private var architecture = SiameseArchitecture()
    @State private var selectedDatasetID: UUID?
    @State private var modelName = ""

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
                    Text("Design a Siamese Neural Network, export a training script, and visualise results")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)

                // Dataset picker
                datasetPickerSection

                // Network diagram
                GroupBox("Network Architecture") {
                    NetworkDiagramView(architecture: $architecture)
                }

                // Conv blocks editor
                convBlocksSection

                // Embedding + comparison
                embeddingSection

                // Hyperparameters
                hyperparametersSection

                // Model summary
                summarySection

                // Action buttons
                actionSection

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    // MARK: - Computed

    private var selectedDataset: PuzzleDataset? {
        guard let id = selectedDatasetID else { return nil }
        return datasetState.datasets.first { $0.id == id }
    }

    private var canCreate: Bool {
        selectedDataset != nil && !modelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canTrain: Bool {
        canCreate && modelState.pythonAvailable == true && !modelState.isTraining
    }

    // MARK: - Sections

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
                .onChange(of: selectedDatasetID) { _, _ in
                    updateInputSizeFromDataset()
                }

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

    private var convBlocksSection: some View {
        GroupBox("Convolutional Blocks") {
            VStack(spacing: 12) {
                ForEach(Array(architecture.convBlocks.enumerated()), id: \.element.id) { index, _ in
                    convBlockEditor(index: index)
                    if index < architecture.convBlocks.count - 1 {
                        Divider()
                    }
                }

                HStack {
                    Button {
                        let lastFilters = architecture.convBlocks.last?.filters ?? 32
                        architecture.convBlocks.append(
                            ConvBlock(filters: min(lastFilters * 2, 512))
                        )
                    } label: {
                        Label("Add Block", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(architecture.convBlocks.count >= 8)

                    if architecture.convBlocks.count > 1 {
                        Button {
                            architecture.convBlocks.removeLast()
                        } label: {
                            Label("Remove Last", systemImage: "minus.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(8)
        }
    }

    private func convBlockEditor(index: Int) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Block \(index + 1)")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Filters:")
                        .font(.caption)
                    TextField("32", value: $architecture.convBlocks[index].filters, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $architecture.convBlocks[index].filters, in: 8...512, step: 16)
                        .labelsHidden()
                }

                HStack(spacing: 4) {
                    Text("Kernel:")
                        .font(.caption)
                    Picker("", selection: $architecture.convBlocks[index].kernelSize) {
                        Text("3x3").tag(3)
                        Text("5x5").tag(5)
                        Text("7x7").tag(7)
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }
            }

            HStack(spacing: 16) {
                Toggle("Batch Norm", isOn: $architecture.convBlocks[index].useBatchNorm)
                    .font(.caption)
                Toggle("Max Pool", isOn: $architecture.convBlocks[index].useMaxPool)
                    .font(.caption)
            }
        }
    }

    private var embeddingSection: some View {
        GroupBox("Embedding & Comparison") {
            VStack(spacing: 8) {
                HStack {
                    Text("Embedding dimension:")
                        .font(.callout)
                    TextField("128", value: $architecture.embeddingDimension, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $architecture.embeddingDimension, in: 16...1024, step: 16)
                        .labelsHidden()
                }

                Picker("Comparison method:", selection: $architecture.comparisonMethod) {
                    ForEach(ComparisonMethod.allCases, id: \.rawValue) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .font(.callout)

                HStack {
                    Text("Dropout:")
                        .font(.callout)
                    Slider(value: $architecture.dropout, in: 0.0...0.8, step: 0.05)
                    Text("\(architecture.dropout, specifier: "%.2f")")
                        .font(.callout.monospacedDigit())
                        .frame(width: 40)
                }
            }
            .padding(8)
        }
    }

    private var hyperparametersSection: some View {
        GroupBox("Training Hyperparameters") {
            VStack(spacing: 8) {
                HStack {
                    Text("Learning rate:")
                        .font(.callout)
                    TextField("0.001", value: $architecture.learningRate, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Batch size:")
                        .font(.callout)
                    Picker("", selection: $architecture.batchSize) {
                        Text("8").tag(8)
                        Text("16").tag(16)
                        Text("32").tag(32)
                        Text("64").tag(64)
                        Text("128").tag(128)
                    }
                    .labelsHidden()
                }

                HStack {
                    Text("Epochs:")
                        .font(.callout)
                    TextField("50", value: $architecture.epochs, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $architecture.epochs, in: 1...500, step: 10)
                        .labelsHidden()
                }

                Picker("Device:", selection: $architecture.devicePreference) {
                    ForEach(DevicePreference.allCases, id: \.rawValue) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .font(.callout)
            }
            .padding(8)
        }
    }

    private var summarySection: some View {
        GroupBox("Summary") {
            VStack(alignment: .leading, spacing: 4) {
                summaryRow("Input", "\(architecture.inputSize) x \(architecture.inputSize) x 3")
                summaryRow("Conv blocks", "\(architecture.convBlocks.count)")
                summaryRow("Flattened size", "\(architecture.flattenedSize)")
                summaryRow("Embedding", "\(architecture.embeddingDimension)-d")
                summaryRow("Comparison", architecture.comparisonMethod.displayName)
                Divider()
                summaryRow("Learning rate", "\(architecture.learningRate)")
                summaryRow("Batch size", "\(architecture.batchSize)")
                summaryRow("Epochs", "\(architecture.epochs)")
            }
            .padding(8)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .fontWeight(.medium)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    createModel(andExport: false, andTrain: false)
                } label: {
                    Label("Create Model", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCreate)

                Button {
                    createModel(andExport: true, andTrain: false)
                } label: {
                    Label("Create & Export...", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!canCreate)

                Button {
                    createModel(andExport: false, andTrain: true)
                } label: {
                    Label("Create & Train", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.green)
                .disabled(!canTrain)
            }

            if !canCreate {
                if selectedDataset == nil {
                    Text("Select a source dataset to continue")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if modelName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Enter a model name to continue")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if modelState.pythonAvailable == false {
                Label("python3 not found - install Python to enable in-app training", systemImage: "exclamationmark.triangle.fill")
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

    private func updateInputSizeFromDataset() {
        guard let dataset = selectedDataset else { return }
        let canvasSize = Int(ceil(Double(dataset.configuration.pieceSize) * 1.75))
        architecture.inputSize = canvasSize
    }

    private func createModel(andExport: Bool, andTrain: Bool) {
        guard let dataset = selectedDataset else { return }
        let name = modelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let model = SiameseModel(
            name: name,
            sourceDatasetID: dataset.id,
            sourceDatasetName: dataset.name,
            architecture: architecture
        )
        modelState.addModel(model)

        if andExport {
            exportModel(model, dataset: dataset)
        }

        if andTrain {
            // Navigate to the model detail view, then start training
            selection = .model(model.id)
            Task {
                await TrainingRunner.train(model: model, dataset: dataset, state: modelState)
            }
        }
    }

    private func exportModel(_ model: SiameseModel, dataset: PuzzleDataset) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export the training package"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try TrainingScriptGenerator.exportTrainingPackage(
                model: model,
                dataset: dataset,
                to: url
            )
            model.status = .exported
            ModelStore.saveModel(model)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
