import Charts
import SwiftUI

/// Detail view for an AutoML study showing trials, charts, and results.
struct AutoMLStudyDetailView: View {
    @ObservedObject var study: AutoMLStudy
    @ObservedObject var autoMLState: AutoMLState
    @ObservedObject var modelState: ModelState
    @ObservedObject var datasetState: DatasetState
    @Binding var selection: SidebarItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Notes
                notesSection

                // Running progress
                if isStudyRunning {
                    runningSection
                }

                // Optimisation history chart
                if !displayTrials.isEmpty {
                    optimisationChartSection
                }

                // Trials table
                if !displayTrials.isEmpty {
                    trialsTableSection
                }

                // Best trial summary
                if let bestTrial = bestCompleteTrial {
                    bestTrialSection(bestTrial)
                }

                // Actions
                actionsSection

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    // MARK: - Computed

    private var isStudyRunning: Bool {
        autoMLState.runningStudyID == study.id && autoMLState.isRunning
    }

    /// Use live trials during running, persisted trials otherwise.
    private var displayTrials: [AutoMLTrial] {
        if isStudyRunning && !autoMLState.liveTrials.isEmpty {
            return autoMLState.liveTrials
        }
        return study.trials
    }

    private var bestCompleteTrial: AutoMLTrial? {
        let completed = displayTrials.filter { $0.state == .complete }
        guard !completed.isEmpty else { return nil }

        let direction = study.configuration.optimisationMetric.direction
        if direction == "maximize" {
            return completed.max(by: { ($0.value ?? -Double.infinity) < ($1.value ?? -Double.infinity) })
        } else {
            return completed.min(by: { ($0.value ?? Double.infinity) < ($1.value ?? Double.infinity) })
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text(study.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                statusBadge(study.status)
            }

            HStack(spacing: 16) {
                Label(study.sourceDatasetName, systemImage: "tablecells")
                Label(study.sourcePresetName, systemImage: "slider.horizontal.3")
                Label(study.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Text("\(study.configuration.numTrials) trials")
                Text(study.configuration.optimisationMetric.displayName)
                if study.configuration.usePruning {
                    Text("Pruning ON")
                }
                Text("\(study.configuration.dimensions.count) params searched")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func statusBadge(_ status: StudyStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColour(status).opacity(0.15))
            .foregroundStyle(statusColour(status))
            .clipShape(Capsule())
    }

    // MARK: - Notes

    private var notesSection: some View {
        GroupBox("Notes") {
            TextEditor(text: Binding(
                get: { study.notes },
                set: { newValue in
                    study.notes = newValue
                    AutoMLStudyStore.saveStudy(study)
                }
            ))
            .font(.callout)
            .frame(minHeight: 50, maxHeight: 100)
        }
    }

    // MARK: - Running Progress

    private var runningSection: some View {
        GroupBox("Running") {
            VStack(alignment: .leading, spacing: 12) {
                // Status
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusText)
                        .font(.callout)
                }

                // Progress bar
                if case .running(let trial, let total) = autoMLState.runningStatus {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(trial), total: Double(total))
                        Text("Trial \(trial)/\(total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Current trial live chart
                if let metrics = autoMLState.currentTrialLiveMetrics,
                   !metrics.trainLoss.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Trial \(autoMLState.currentTrialNumber) - Epoch \(autoMLState.currentTrialEpoch)/\(autoMLState.currentTrialTotalEpochs)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Chart {
                            ForEach(metrics.trainLoss, id: \.epoch) { point in
                                LineMark(
                                    x: .value("Epoch", point.epoch),
                                    y: .value("Loss", point.value),
                                    series: .value("Series", "Train Loss")
                                )
                                .foregroundStyle(.blue)
                            }
                            ForEach(metrics.validLoss, id: \.epoch) { point in
                                LineMark(
                                    x: .value("Epoch", point.epoch),
                                    y: .value("Loss", point.value),
                                    series: .value("Series", "Valid Loss")
                                )
                                .foregroundStyle(.orange)
                            }
                        }
                        .frame(height: 120)
                        .chartLegend(position: .top)
                    }
                }

                // Log
                GroupBox("Log") {
                    ScrollView {
                        ScrollViewReader { proxy in
                            LazyVStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(autoMLState.runningLog.suffix(100).enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .id(idx)
                                }
                            }
                            .onChange(of: autoMLState.runningLog.count) { _, _ in
                                if !autoMLState.runningLog.isEmpty {
                                    proxy.scrollTo(autoMLState.runningLog.count - 1)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }

                // Cancel button
                Button(role: .destructive) {
                    AutoMLRunner.cancel(state: autoMLState)
                } label: {
                    Label("Cancel Study", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var statusText: String {
        switch autoMLState.runningStatus {
        case .idle: return "Idle"
        case .preparingEnvironment: return "Preparing environment..."
        case .installingDependencies: return "Installing dependencies..."
        case .uploadingDataset: return "Uploading dataset..."
        case .running(let trial, let total): return "Running trial \(trial)/\(total)..."
        case .downloadingResults: return "Downloading results..."
        case .importingResults: return "Importing results..."
        case .completed: return "Completed"
        case .failed(let reason): return "Failed: \(reason)"
        case .cancelled: return "Cancelled"
        }
    }

    // MARK: - Optimisation History Chart

    private var optimisationChartSection: some View {
        GroupBox("Optimisation History") {
            Chart {
                ForEach(displayTrials.filter { $0.state == .complete }) { trial in
                    PointMark(
                        x: .value("Trial", trial.trialNumber),
                        y: .value("Value", trial.value ?? 0)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(30)
                }

                ForEach(displayTrials.filter { $0.state == .pruned }) { trial in
                    PointMark(
                        x: .value("Trial", trial.trialNumber),
                        y: .value("Value", trial.bestValidAccuracy ?? 0)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(20)
                    .symbol(.cross)
                }

                // Best value line
                if let best = bestCompleteTrial?.value {
                    RuleMark(y: .value("Best", best))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                }
            }
            .frame(height: 200)
            .chartLegend(position: .top)
        }
    }

    // MARK: - Trials Table

    private var trialsTableSection: some View {
        GroupBox("Trial Results") {
            AutoMLTrialsTableView(
                trials: displayTrials,
                bestTrialNumber: bestCompleteTrial?.trialNumber,
                searchDimensions: study.configuration.dimensions
            )
        }
    }

    // MARK: - Best Trial

    private func bestTrialSection(_ trial: AutoMLTrial) -> some View {
        GroupBox("Best Trial") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("Trial \(trial.trialNumber)")
                        .fontWeight(.semibold)
                    Spacer()
                    if let value = trial.value {
                        Text(String(format: "%.6f", value))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }

                // All params
                ForEach(Array(trial.params.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                    HStack {
                        Text(key)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(value)
                            .font(.system(.callout, design: .monospaced))
                    }
                    .font(.caption)
                }

                if let acc = trial.bestValidAccuracy {
                    HStack {
                        Text("Best Valid Accuracy")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.4f", acc))
                            .font(.system(.callout, design: .monospaced))
                    }
                    .font(.caption)
                }

                if let duration = trial.duration {
                    HStack {
                        Text("Duration")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1fs", duration))
                            .font(.system(.callout, design: .monospaced))
                    }
                    .font(.caption)
                }

                // View best model button
                if let modelID = study.bestModelID {
                    Button {
                        selection = .model(modelID)
                    } label: {
                        Label("View Best Model", systemImage: "brain")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 8) {
                if study.status == .configured || study.status == .cancelled {
                    Button {
                        resumeStudy()
                    } label: {
                        Label(
                            study.status == .cancelled ? "Resume Study" : "Run Study",
                            systemImage: "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(autoMLState.isRunning || modelState.isTraining)
                }

                if study.status == .completed && study.bestModelID == nil {
                    Button {
                        importBestTrial()
                    } label: {
                        Label("Import Best Trial as Model", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Actions Implementation

    private func resumeStudy() {
        guard let dataset = datasetState.datasets.first(where: { $0.id == study.sourceDatasetID }) else {
            return
        }

        Task {
            await AutoMLRunner.train(
                study: study,
                dataset: dataset,
                state: autoMLState,
                modelState: modelState
            )
        }
    }

    private func importBestTrial() {
        guard let bestTrial = bestCompleteTrial else { return }

        let arch = AutoMLRunner.architectureFromParams(
            study.configuration.baseArchitecture,
            bestTrial.params
        )

        let model = SiameseModel(
            name: "\(study.name) - Best (Trial \(bestTrial.trialNumber))",
            sourceDatasetID: study.sourceDatasetID,
            sourceDatasetName: study.sourceDatasetName,
            architecture: arch,
            status: .designed,
            sourcePresetName: study.sourcePresetName,
            notes: "Imported from AutoML study '\(study.name)'. Trial \(bestTrial.trialNumber)."
        )

        modelState.addModel(model)
        study.bestModelID = model.id
        AutoMLStudyStore.saveStudy(study)
        selection = .model(model.id)
    }

    // MARK: - Helpers

    private func statusColour(_ status: StudyStatus) -> Color {
        switch status {
        case .configured: return .blue
        case .running: return .orange
        case .completed: return .green
        case .cancelled: return .yellow
        case .failed: return .red
        }
    }
}
