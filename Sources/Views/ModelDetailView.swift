import Charts
import SwiftUI

/// Detail view for a persisted SiameseModel.
/// Shows architecture summary, export/import actions, and training metric charts.
struct ModelDetailView: View {
    @ObservedObject var model: SiameseModel
    @ObservedObject var modelState: ModelState
    @ObservedObject var datasetState: DatasetState

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                architectureSection
                trainingSection
                exportSection
                importSection

                if let metrics = activeMetrics {
                    metricsCharts(metrics)
                    testResultsSection(metrics)
                }

                actionsSection

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    /// Show live metrics during training, otherwise the model's final metrics.
    private var activeMetrics: TrainingMetrics? {
        if isTrainingThisModel, let live = modelState.liveMetrics,
           !live.trainLoss.isEmpty {
            return live
        }
        return model.metrics
    }

    /// True when this model is actively training (in-progress states).
    private var isTrainingThisModel: Bool {
        modelState.trainingModelID == model.id && modelState.isTraining
    }

    /// True when this model has a training session (active or just finished/failed/cancelled).
    /// Used to keep the log visible after terminal states.
    private var hasTrainingSession: Bool {
        modelState.trainingModelID == model.id && !modelState.trainingLog.isEmpty
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundStyle(.indigo)
            Text(model.name)
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                statusBadge(model.status)
                Label(model.sourceDatasetName, systemImage: "brain.filled.head.profile")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label(Self.dateFormatter.string(from: model.createdAt), systemImage: "calendar")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func statusBadge(_ status: ModelStatus) -> some View {
        let colour: Color = switch status {
        case .designed: .blue
        case .exported: .orange
        case .training: .yellow
        case .trained: .green
        }
        return Text(status.rawValue.capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(colour)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colour.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Architecture

    private var architectureSection: some View {
        GroupBox("Architecture") {
            VStack(spacing: 8) {
                // Read-only compact diagram
                NetworkDiagramView(architecture: .constant(model.architecture))
                    .scaleEffect(0.85)
                    .frame(maxHeight: 300)

                Divider()

                VStack(spacing: 4) {
                    configRow("Input size", "\(model.architecture.inputSize) x \(model.architecture.inputSize)")
                    configRow("Conv blocks", "\(model.architecture.convBlocks.count)")
                    configRow("Embedding", "\(model.architecture.embeddingDimension)-d")
                    configRow("Comparison", model.architecture.comparisonMethod.displayName)
                    configRow("Dropout", String(format: "%.2f", model.architecture.dropout))
                    Divider()
                    configRow("Learning rate", "\(model.architecture.learningRate)")
                    configRow("Batch size", "\(model.architecture.batchSize)")
                    configRow("Epochs", "\(model.architecture.epochs)")
                }
            }
            .padding(8)
        }
    }

    // MARK: - Training

    private var trainingSection: some View {
        GroupBox("Training") {
            VStack(spacing: 12) {
                if isTrainingThisModel {
                    activeTrainingView
                } else if hasTrainingSession {
                    // Terminal state (failed/cancelled/completed) - keep log visible
                    terminalTrainingView
                } else if model.status == .trained {
                    trainedView
                } else {
                    idleTrainingView
                }
            }
            .padding(8)
        }
    }

    private var idleTrainingView: some View {
        VStack(spacing: 8) {
            Text("Run training directly from the app. Requires Python 3 with PyTorch.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                startTraining()
            } label: {
                Label("Train", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(modelState.pythonAvailable == false || modelState.isTraining)

            if modelState.pythonAvailable == false {
                Label("python3 not found on this system", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if modelState.isTraining {
                Text("Another model is currently training")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if modelState.pythonAvailable == nil {
                modelState.pythonAvailable = await TrainingRunner.isPythonAvailable()
            }
        }
    }

    private var activeTrainingView: some View {
        VStack(spacing: 12) {
            // Status label
            HStack {
                trainingStatusLabel
                Spacer()
                Button(role: .destructive) {
                    TrainingRunner.cancel(state: modelState)
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }

            // Progress bar
            if case .training(let epoch, let total) = modelState.trainingStatus {
                VStack(spacing: 4) {
                    ProgressView(value: Double(epoch), total: Double(total))
                    Text("Epoch \(epoch)/\(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            // Log viewer
            trainingLogView
        }
    }

    @ViewBuilder
    private var trainingStatusLabel: some View {
        switch modelState.trainingStatus {
        case .preparingEnvironment:
            Label("Preparing environment...", systemImage: "gearshape")
                .foregroundStyle(.secondary)
        case .installingDependencies:
            Label("Installing dependencies...", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .training(let epoch, let total):
            Label("Training \(epoch)/\(total)", systemImage: "play.circle.fill")
                .foregroundStyle(.yellow)
        case .importingResults:
            Label("Importing results...", systemImage: "arrow.down.doc")
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var terminalTrainingView: some View {
        VStack(spacing: 12) {
            // Status message
            HStack {
                switch modelState.trainingStatus {
                case .failed(let reason):
                    Label("Training failed: \(reason)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                case .cancelled:
                    Label("Training cancelled", systemImage: "stop.circle.fill")
                        .foregroundStyle(.orange)
                case .completed:
                    Label("Training complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                default:
                    EmptyView()
                }
                Spacer()
                Button {
                    modelState.clearTrainingState()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Log viewer (persisted from the session)
            trainingLogView

            // Retry button for failures
            if case .failed = modelState.trainingStatus {
                Button {
                    modelState.clearTrainingState()
                    startTraining()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var trainedView: some View {
        VStack(spacing: 8) {
            Label("Training complete", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Button {
                startTraining()
            } label: {
                Label("Retrain", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(modelState.pythonAvailable == false || modelState.isTraining)
        }
    }

    private var trainingLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(modelState.trainingLog.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: modelState.trainingLog.count) { _, _ in
                if let last = modelState.trainingLog.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func startTraining() {
        guard let dataset = datasetState.datasets.first(where: { $0.id == model.sourceDatasetID }) else {
            let alert = NSAlert()
            alert.messageText = "Dataset Not Found"
            alert.informativeText = "The source dataset (\(model.sourceDatasetName)) could not be found. It may have been deleted."
            alert.runModal()
            return
        }

        Task {
            await TrainingRunner.train(model: model, dataset: dataset, state: modelState)
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        GroupBox("Export") {
            VStack(spacing: 8) {
                Text("Export a self-contained PyTorch training package with the dataset and training script.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    exportTrainingPackage()
                } label: {
                    Label("Export Training Package...", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
        }
    }

    // MARK: - Import

    private var importSection: some View {
        GroupBox("Import Results") {
            VStack(spacing: 8) {
                Text("After training, import the generated metrics.json and optionally the Core ML model.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        importMetrics()
                    } label: {
                        Label("Import metrics.json...", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        importCoreMLModel()
                    } label: {
                        Label("Import .mlpackage...", systemImage: "cpu")
                    }
                    .buttonStyle(.bordered)
                }

                if model.hasImportedModel {
                    Label("Core ML model imported", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Metrics Charts

    @ViewBuilder
    private func metricsCharts(_ metrics: TrainingMetrics) -> some View {
        GroupBox("Loss") {
            Chart {
                ForEach(metrics.trainLoss) { point in
                    LineMark(
                        x: .value("Epoch", point.epoch),
                        y: .value("Loss", point.value)
                    )
                    .foregroundStyle(by: .value("Series", "Train"))
                }
                ForEach(metrics.validLoss) { point in
                    LineMark(
                        x: .value("Epoch", point.epoch),
                        y: .value("Loss", point.value)
                    )
                    .foregroundStyle(by: .value("Series", "Validation"))
                }
                if let bestEpoch = metrics.bestEpoch {
                    RuleMark(x: .value("Best Epoch", bestEpoch))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Best: \(bestEpoch)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale([
                "Train": Color.blue,
                "Validation": Color.orange,
            ])
            .frame(height: 200)
            .padding(8)
        }

        GroupBox("Accuracy") {
            Chart {
                ForEach(metrics.trainAccuracy) { point in
                    LineMark(
                        x: .value("Epoch", point.epoch),
                        y: .value("Accuracy", point.value)
                    )
                    .foregroundStyle(by: .value("Series", "Train"))
                }
                ForEach(metrics.validAccuracy) { point in
                    LineMark(
                        x: .value("Epoch", point.epoch),
                        y: .value("Accuracy", point.value)
                    )
                    .foregroundStyle(by: .value("Series", "Validation"))
                }
                if let bestEpoch = metrics.bestEpoch {
                    RuleMark(x: .value("Best Epoch", bestEpoch))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                }
            }
            .chartForegroundStyleScale([
                "Train": Color.blue,
                "Validation": Color.orange,
            ])
            .chartYScale(domain: 0...1)
            .frame(height: 200)
            .padding(8)
        }
    }

    // MARK: - Test Results

    @ViewBuilder
    private func testResultsSection(_ metrics: TrainingMetrics) -> some View {
        let hasTestStats = metrics.testAccuracy != nil || metrics.testLoss != nil

        if hasTestStats {
            GroupBox("Test Results") {
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        if let acc = metrics.testAccuracy {
                            statBadge(value: String(format: "%.1f%%", acc * 100), label: "Accuracy", colour: .green)
                        }
                        if let loss = metrics.testLoss {
                            statBadge(value: String(format: "%.4f", loss), label: "Loss", colour: .red)
                        }
                        if let prec = metrics.testPrecision {
                            statBadge(value: String(format: "%.3f", prec), label: "Precision", colour: .blue)
                        }
                        if let rec = metrics.testRecall {
                            statBadge(value: String(format: "%.3f", rec), label: "Recall", colour: .orange)
                        }
                        if let f1 = metrics.testF1 {
                            statBadge(value: String(format: "%.3f", f1), label: "F1", colour: .purple)
                        }
                    }

                    HStack(spacing: 16) {
                        if let duration = metrics.trainingDurationSeconds {
                            let formatted = duration < 60
                                ? String(format: "%.1fs", duration)
                                : String(format: "%.1fm", duration / 60)
                            statBadge(value: formatted, label: "Duration", colour: .teal)
                        }
                        if let best = metrics.bestEpoch {
                            statBadge(value: "\(best)", label: "Best Epoch", colour: .indigo)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func statBadge(value: String, label: String, colour: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(colour.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                modelState.deleteModel(model)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Config Row

    private func configRow(_ label: String, _ value: String) -> some View {
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

    // MARK: - Import/Export Actions

    private func exportTrainingPackage() {
        guard let dataset = datasetState.datasets.first(where: { $0.id == model.sourceDatasetID }) else {
            let alert = NSAlert()
            alert.messageText = "Dataset Not Found"
            alert.informativeText = "The source dataset (\(model.sourceDatasetName)) could not be found. It may have been deleted."
            alert.runModal()
            return
        }

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

    private func importMetrics() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Select the metrics.json file from training"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let metrics = try JSONDecoder().decode(TrainingMetrics.self, from: data)
            model.metrics = metrics
            model.status = .trained
            ModelStore.saveModel(model)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import Failed"
            alert.informativeText = "Could not parse metrics.json: \(error.localizedDescription)"
            alert.runModal()
        }
    }

    private func importCoreMLModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.message = "Select the model.mlpackage directory"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ModelStore.importCoreMLModel(from: url, for: model.id)
            model.hasImportedModel = true
            ModelStore.saveModel(model)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
