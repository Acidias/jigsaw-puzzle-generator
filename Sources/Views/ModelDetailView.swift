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
                exportSection
                importSection

                if let metrics = model.metrics {
                    metricsCharts(metrics)
                    testResultsSection(metrics)
                }

                actionsSection

                Spacer(minLength: 20)
            }
            .padding()
        }
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
