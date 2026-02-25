import SwiftUI

struct DatasetGenerationPanel: View {
    @ObservedObject var datasetState: DatasetState
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 40))
                        .foregroundStyle(.purple)
                    Text("Dataset Generation")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Generate structured ML training datasets from 2-piece jigsaw puzzles")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)

                // Project picker
                projectPickerSection

                // Project info & capacity
                if selectedProject != nil {
                    projectInfoSection
                }

                // Normalisation settings
                normalisationSection

                // Generation settings
                generationSettingsSection

                // Category counts
                categoryCountsSection

                // Split ratios
                splitRatiosSection

                // Output directory
                outputDirectorySection

                // Generate button + progress
                generateSection

                // Log viewer
                if !datasetState.logMessages.isEmpty {
                    logSection
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .disabled(datasetState.isRunning)
    }

    // MARK: - Computed Properties

    private var selectedProject: PuzzleProject? {
        guard let id = datasetState.configuration.projectID else { return nil }
        return appState.projects.first { $0.id == id }
    }

    private var imageCount: Int {
        selectedProject?.images.count ?? 0
    }

    // MARK: - Sections

    private var projectPickerSection: some View {
        GroupBox("Project") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Project:", selection: $datasetState.configuration.projectID) {
                    Text("Select a project...").tag(nil as UUID?)
                    ForEach(appState.projects) { project in
                        Text("\(project.name) (\(project.images.count) images)")
                            .tag(project.id as UUID?)
                    }
                }
                .font(.callout)

                if appState.projects.isEmpty {
                    Text("No projects available. Create a project and add images first.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
        }
    }

    private var projectInfoSection: some View {
        GroupBox("Capacity") {
            VStack(alignment: .leading, spacing: 8) {
                let cuts = datasetState.configuration.cutsPerImage

                HStack {
                    Label("\(imageCount) images", systemImage: "photo.stack")
                    Spacer()
                    Label("\(cuts) cuts per image", systemImage: "scissors")
                }
                .font(.callout)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    capacityRow(
                        "Correct",
                        pool: datasetState.correctPool(imageCount: imageCount),
                        requested: datasetState.configuration.correctCount
                    )
                    capacityRow(
                        "Shape match",
                        pool: datasetState.shapeMatchPool(imageCount: imageCount),
                        requested: datasetState.configuration.wrongShapeMatchCount
                    )
                    capacityRow(
                        "Image match",
                        pool: datasetState.imageMatchPool(imageCount: imageCount),
                        requested: datasetState.configuration.wrongImageMatchCount
                    )
                    capacityRow(
                        "Nothing",
                        pool: datasetState.nothingPool(imageCount: imageCount),
                        requested: datasetState.configuration.wrongNothingCount
                    )
                }

                if imageCount < 2 && datasetState.configuration.wrongShapeMatchCount > 0 {
                    Label("Shape match requires at least 2 images", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if cuts < 2 && datasetState.configuration.wrongImageMatchCount > 0 {
                    Label("Image match requires at least 2 cuts", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
        }
    }

    private func capacityRow(_ label: String, pool: Int, requested: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 100, alignment: .leading)
            Text("Pool: \(pool)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if requested > pool {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text("Exceeds pool!")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    private var normalisationSection: some View {
        GroupBox("Normalisation") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Piece size:")
                        .font(.callout)
                    TextField(
                        "224",
                        value: $datasetState.configuration.pieceSize,
                        format: .number
                    )
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    Stepper("", value: $datasetState.configuration.pieceSize, in: 32...1024, step: 16)
                        .labelsHidden()
                    Text("px")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Picker("Fill:", selection: $datasetState.configuration.pieceFill) {
                    Text("Black").tag(PieceFill.black)
                    Text("White").tag(PieceFill.white)
                    Text("None (transparent)").tag(PieceFill.none)
                    Text("Average grey").tag(PieceFill.grey)
                }
                .font(.callout)

                let canvasSize = Int(ceil(Double(datasetState.configuration.pieceSize) * 1.75))
                Text("Each piece image: \(canvasSize) x \(canvasSize) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var generationSettingsSection: some View {
        GroupBox("Generation") {
            HStack(spacing: 8) {
                Text("Cuts per image:")
                    .font(.callout)
                Stepper(
                    "\(datasetState.configuration.cutsPerImage)",
                    value: $datasetState.configuration.cutsPerImage,
                    in: 2...50
                )
                .font(.callout)
            }
            .padding(8)
        }
    }

    private var categoryCountsSection: some View {
        GroupBox("Pair Counts (per category)") {
            VStack(spacing: 8) {
                categoryCountRow("Correct:", value: $datasetState.configuration.correctCount)
                categoryCountRow("Shape match (wrong):", value: $datasetState.configuration.wrongShapeMatchCount)
                categoryCountRow("Image match (wrong):", value: $datasetState.configuration.wrongImageMatchCount)
                categoryCountRow("Nothing (wrong):", value: $datasetState.configuration.wrongNothingCount)

                Divider()

                HStack {
                    Text("Total pairs:")
                        .font(.callout)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(datasetState.configuration.totalPairs)")
                        .font(.callout)
                        .fontWeight(.semibold)
                }
            }
            .padding(8)
        }
    }

    private func categoryCountRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .frame(width: 180, alignment: .leading)
            TextField("500", value: value, format: .number)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
            Stepper("", value: value, in: 0...10000, step: 50)
                .labelsHidden()
        }
    }

    private var splitRatiosSection: some View {
        GroupBox("Train/Test/Valid Split") {
            VStack(spacing: 8) {
                splitRatioRow("Train:", value: $datasetState.configuration.trainRatio)
                splitRatioRow("Test:", value: $datasetState.configuration.testRatio)
                splitRatioRow("Valid:", value: $datasetState.configuration.validRatio)

                let sum = datasetState.configuration.trainRatio
                    + datasetState.configuration.testRatio
                    + datasetState.configuration.validRatio
                let isValid = abs(sum - 1.0) < 0.01
                HStack {
                    Text("Sum: \(sum, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(isValid ? Color.secondary : Color.red)
                    if !isValid {
                        Text("(must equal 1.0)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(8)
        }
    }

    private func splitRatioRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .frame(width: 50, alignment: .leading)
            Slider(value: value, in: 0.0...1.0, step: 0.05)
            Text("\(value.wrappedValue, specifier: "%.2f")")
                .font(.callout.monospacedDigit())
                .frame(width: 40)
        }
    }

    private var outputDirectorySection: some View {
        GroupBox("Output Directory") {
            HStack {
                if let dir = datasetState.configuration.outputDirectory {
                    Text(dir.path)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No directory selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                Spacer()
                Button("Choose...") {
                    chooseOutputDirectory()
                }
            }
            .padding(8)
        }
    }

    private var generateSection: some View {
        VStack(spacing: 12) {
            if case .generating(let phase, let progress) = datasetState.status {
                VStack(spacing: 6) {
                    ProgressView(value: progress) {
                        Text(phase)
                            .font(.callout)
                    }
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .completed(let count) = datasetState.status {
                Label("\(count) pairs generated successfully", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            if case .failed(let reason) = datasetState.status {
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Button {
                startGeneration()
            } label: {
                Label("Generate Dataset", systemImage: "brain")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canGenerate)
        }
    }

    private var logSection: some View {
        GroupBox("Log") {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(datasetState.logMessages.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(8)
        }
    }

    // MARK: - Actions

    private var canGenerate: Bool {
        guard selectedProject != nil,
              datasetState.configuration.outputDirectory != nil,
              !datasetState.isRunning else { return false }

        let sum = datasetState.configuration.trainRatio
            + datasetState.configuration.testRatio
            + datasetState.configuration.validRatio
        guard abs(sum - 1.0) < 0.01 else { return false }

        // Check minimum image count
        if imageCount < 1 { return false }

        return true
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for the dataset output"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        datasetState.configuration.outputDirectory = url
    }

    private func startGeneration() {
        guard let project = selectedProject else { return }
        Task {
            await DatasetGenerator.generate(state: datasetState, project: project)
        }
    }
}
