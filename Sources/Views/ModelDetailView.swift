import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Detail view for a persisted SiameseModel.
/// Shows architecture summary, training controls, and metric charts.
struct ModelDetailView: View {
    @ObservedObject var model: SiameseModel
    @ObservedObject var modelState: ModelState
    @ObservedObject var datasetState: DatasetState

    @State private var connectionTestResult: String?
    @State private var isTestingConnection = false
    @State private var isEditingArchitecture = false

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
                notesSection
                architectureSection
                trainingSection

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

            // Experiment metadata row
            HStack(spacing: 12) {
                if let presetName = model.sourcePresetName {
                    Label(presetName, systemImage: "rectangle.stack")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let hash = model.scriptHash {
                    Label(String(hash.prefix(8)), systemImage: "number")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let trainedAt = model.trainedAt {
                    Label(Self.dateFormatter.string(from: trainedAt), systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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

    // MARK: - Notes

    private var notesSection: some View {
        GroupBox("Notes") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.notes)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .onChange(of: model.notes) { _, _ in
                        ModelStore.saveModel(model)
                    }
                if model.notes.isEmpty {
                    Text("Add experiment notes...")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Architecture

    private var architectureSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                // Header with edit toggle
                HStack {
                    Label("Architecture", systemImage: "cpu")
                        .font(.headline)
                    Spacer()
                    if !isTrainingThisModel {
                        Button {
                            isEditingArchitecture.toggle()
                        } label: {
                            Label(
                                isEditingArchitecture ? "Done" : "Edit",
                                systemImage: isEditingArchitecture ? "checkmark.circle" : "pencil"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if isEditingArchitecture {
                    ArchitectureEditorView(architecture: $model.architecture)
                        .onChange(of: model.architecture) { _, _ in
                            handleArchitectureChange()
                        }
                } else {
                    // Read-only compact view
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
            }
            .padding(8)
        }
    }

    private func handleArchitectureChange() {
        // Architecture change invalidates previous training results
        if model.status == .trained || model.status == .exported {
            model.metrics = nil
            model.status = .designed
        }
        modelState.updateModel(model)
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
            Text("Run training directly from the app or on a remote GPU via SSH.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Training target picker
            Picker("Target:", selection: $modelState.trainingTarget) {
                ForEach(TrainingTarget.allCases, id: \.rawValue) { target in
                    Label(target.displayName, systemImage: target.icon).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            // Cloud config form (inline)
            if modelState.trainingTarget == .cloud {
                cloudConfigForm
            }

            Button {
                startTraining()
            } label: {
                Label("Train", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!canStartTraining || modelState.isTraining)

            if modelState.trainingTarget == .local {
                if modelState.pythonAvailable == false {
                    Label("python3 not found on this system", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else if !modelState.cloudConfig.isValid {
                Label("Enter a valid hostname and SSH key path", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if modelState.isTraining {
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

    private var canStartTraining: Bool {
        if modelState.trainingTarget == .local {
            return modelState.pythonAvailable != false
        } else {
            return modelState.cloudConfig.isValid
        }
    }

    private var cloudConfigForm: some View {
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

            // Test connection button
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

    private var activeTrainingView: some View {
        VStack(spacing: 12) {
            // Status label
            HStack {
                trainingStatusLabel
                Spacer()
                if modelState.trainingTarget == .cloud {
                    Label(modelState.cloudConfig.hostname, systemImage: "cloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    cancelTraining()
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
        case .uploadingDataset:
            Label("Uploading dataset...", systemImage: "arrow.up.circle")
                .foregroundStyle(.secondary)
        case .training(let epoch, let total):
            Label("Training \(epoch)/\(total)", systemImage: "play.circle.fill")
                .foregroundStyle(.yellow)
        case .importingResults:
            Label("Importing results...", systemImage: "arrow.down.doc")
                .foregroundStyle(.secondary)
        case .downloadingResults:
            Label("Downloading results...", systemImage: "arrow.down.circle")
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
            .disabled(!canStartTraining || modelState.isTraining)
        }
    }

    private var trainingLogText: String {
        modelState.trainingLog.joined(separator: "\n")
    }

    private var trainingLogView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(trainingLogText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .id("log-bottom")
                }
                .frame(maxHeight: 200)
                .onChange(of: modelState.trainingLog.count) { _, _ in
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(trainingLogText, forType: .string)
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(trainingLogText.isEmpty)
            }
            .padding(4)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private func cancelTraining() {
        if modelState.trainingTarget == .cloud {
            CloudTrainingRunner.cancel(state: modelState)
        } else {
            TrainingRunner.cancel(state: modelState)
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
                        if let threshold = metrics.optimalThreshold {
                            statBadge(value: String(format: "%.2f", threshold), label: "Threshold", colour: .cyan)
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

            if let cm = metrics.confusionMatrix {
                confusionMatrixView(cm)
            }

            if let perCategory = metrics.perCategoryResults, !perCategory.isEmpty {
                perCategoryView(perCategory)
            }

            if let std = metrics.standardisedResults, !std.isEmpty {
                standardisedResultsView(std)
            }
        }
    }

    // MARK: - Standardised Results

    private func standardisedResultsView(_ results: [StandardisedResult]) -> some View {
        GroupBox("Standardised Operating Points") {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Target P")
                        .frame(width: 70, alignment: .leading)
                    Text("Threshold")
                        .frame(width: 75)
                    Text("Precision")
                        .frame(width: 75)
                    Text("Recall")
                        .frame(width: 75)
                    Text("F1")
                        .frame(width: 60)
                    Text("Accuracy")
                        .frame(width: 75)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)

                Divider()

                ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 0) {
                        Text(String(format: ">=%.0f%%", r.precisionTarget * 100))
                            .frame(width: 70, alignment: .leading)
                        Text(String(format: "%.2f", r.threshold))
                            .frame(width: 75)
                        Text(String(format: "%.3f", r.precision))
                            .frame(width: 75)
                        Text(String(format: "%.3f", r.recall))
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                            .frame(width: 75)
                        Text(String(format: "%.3f", r.f1))
                            .frame(width: 60)
                        Text(String(format: "%.1f%%", r.accuracy * 100))
                            .frame(width: 75)
                    }
                    .font(.callout.monospacedDigit())
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)

                    if r.precisionTarget != results.last?.precisionTarget {
                        Divider()
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Confusion Matrix

    private func confusionMatrixView(_ cm: ConfusionMatrix) -> some View {
        let total = cm.truePositives + cm.falsePositives + cm.falseNegatives + cm.trueNegatives
        return GroupBox("Confusion Matrix") {
            VStack(spacing: 0) {
                // Column headers
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 110, height: 28)
                    Text("Predicted Match")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                    Text("Predicted Non-match")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }

                // Actual Match row
                HStack(spacing: 0) {
                    Text("Actual\nMatch")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                    cmCell(
                        value: cm.truePositives, total: total,
                        label: "TP", colour: .green
                    )
                    cmCell(
                        value: cm.falseNegatives, total: total,
                        label: "FN", colour: .red
                    )
                }

                // Actual Non-match row
                HStack(spacing: 0) {
                    Text("Actual\nNon-match")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                    cmCell(
                        value: cm.falsePositives, total: total,
                        label: "FP", colour: .red
                    )
                    cmCell(
                        value: cm.trueNegatives, total: total,
                        label: "TN", colour: .green
                    )
                }
            }
            .padding(8)
        }
    }

    private func cmCell(value: Int, total: Int, label: String, colour: Color) -> some View {
        let pct = total > 0 ? Double(value) / Double(total) * 100 : 0
        return VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.monospacedDigit())
                .fontWeight(.bold)
            Text("\(label) - \(String(format: "%.1f%%", pct))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(colour.opacity(0.08))
        .border(colour.opacity(0.2), width: 0.5)
    }

    // MARK: - Per-Category Results

    private func perCategoryView(_ results: [String: CategoryResult]) -> some View {
        let order = ["correct", "wrong_shape_match", "wrong_image_match", "wrong_nothing"]
        let sorted = order.compactMap { key in
            results[key].map { (key, $0) }
        } + results.filter { !order.contains($0.key) }.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }

        return GroupBox("Per-Category Breakdown") {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("Category")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Total")
                        .frame(width: 50)
                    Text("Match")
                        .frame(width: 50)
                    Text("Non-match")
                        .frame(width: 70)
                    Text("Accuracy")
                        .frame(width: 70)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)

                Divider()

                ForEach(Array(sorted.enumerated()), id: \.offset) { _, entry in
                    let (category, result) = entry
                    let isCorrect = category == "correct"
                    // For "correct": accuracy = predictedMatch/total
                    // For wrong categories: accuracy = predictedNonMatch/total
                    let accuracy = result.total > 0
                        ? Double(isCorrect ? result.predictedMatch : result.predictedNonMatch) / Double(result.total)
                        : 0

                    HStack(spacing: 0) {
                        Text(categoryDisplayName(category))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(result.total)")
                            .frame(width: 50)
                        Text("\(result.predictedMatch)")
                            .foregroundStyle(isCorrect ? .green : (result.predictedMatch > 0 ? .red : .primary))
                            .frame(width: 50)
                        Text("\(result.predictedNonMatch)")
                            .foregroundStyle(isCorrect ? (result.predictedNonMatch > 0 ? .red : .primary) : .green)
                            .frame(width: 70)
                        Text(String(format: "%.1f%%", accuracy * 100))
                            .fontWeight(.medium)
                            .foregroundStyle(accuracy >= 0.8 ? .green : accuracy >= 0.5 ? .orange : .red)
                            .frame(width: 70)
                    }
                    .font(.callout.monospacedDigit())
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)

                    if category != sorted.last?.0 {
                        Divider()
                    }
                }
            }
            .padding(4)
        }
    }

    private func categoryDisplayName(_ raw: String) -> String {
        switch raw {
        case "correct": return "Correct"
        case "wrong_shape_match": return "Wrong shape match"
        case "wrong_image_match": return "Wrong image match"
        case "wrong_nothing": return "Wrong nothing"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
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
            if model.metrics != nil {
                Button {
                    exportReport()
                } label: {
                    Label("Export Report", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                modelState.deleteModel(model)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(model.name.sanitisedForFilename())_report.json"
        panel.message = "Export training report"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ModelStore.exportReport(model: model, datasets: datasetState.datasets, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
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

}
