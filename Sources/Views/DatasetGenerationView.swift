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

                // Generate button + progress
                generateSection

                // Log viewer
                if !datasetState.logMessages.isEmpty {
                    logSection
                }

                // Persisted datasets
                if !datasetState.datasets.isEmpty {
                    datasetsListSection
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
              !datasetState.isRunning else { return false }

        let sum = datasetState.configuration.trainRatio
            + datasetState.configuration.testRatio
            + datasetState.configuration.validRatio
        guard abs(sum - 1.0) < 0.01 else { return false }

        if imageCount < 1 { return false }

        return true
    }

    private func startGeneration() {
        guard let project = selectedProject else { return }
        Task {
            await DatasetGenerator.generate(state: datasetState, project: project)
        }
    }

    private var datasetsListSection: some View {
        GroupBox("Datasets") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(datasetState.datasets) { dataset in
                    DatasetRowView(dataset: dataset, datasetState: datasetState)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Dataset Row

private struct DatasetRowView: View {
    @ObservedObject var dataset: PuzzleDataset
    @ObservedObject var datasetState: DatasetState

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dataset.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(dataset.totalPairs) pairs - \(Self.dateFormatter.string(from: dataset.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(dataset.sourceProjectName)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename...") {
                promptRename()
            }
            Button("Export...") {
                exportDataset()
            }
            Divider()
            Button("Delete", role: .destructive) {
                datasetState.deleteDataset(dataset)
            }
        }
    }

    private func promptRename() {
        let alert = NSAlert()
        alert.messageText = "Rename Dataset"
        alert.informativeText = "Enter a new name for the dataset."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = dataset.name
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty {
                dataset.name = newName
                DatasetStore.saveDataset(dataset)
            }
        }
    }

    private func exportDataset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export the dataset"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DatasetStore.exportDataset(dataset, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

// MARK: - Dataset Detail View

struct DatasetDetailView: View {
    @ObservedObject var dataset: PuzzleDataset
    @ObservedObject var datasetState: DatasetState
    @State private var samplePairs: [SamplePair] = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "brain.filled.head.profile")
                        .font(.system(size: 48))
                        .foregroundStyle(.purple)
                    Text(dataset.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 16) {
                        Label(dataset.sourceProjectName, systemImage: "folder")
                        Label(Self.dateFormatter.string(from: dataset.createdAt), systemImage: "calendar")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                // Stats bar
                HStack(spacing: 24) {
                    statBadge(value: "\(dataset.totalPairs)", label: "Total pairs", icon: "square.grid.2x2", colour: .purple)
                    let canvasSize = Int(ceil(Double(dataset.configuration.pieceSize) * 1.75))
                    statBadge(value: "\(canvasSize)px", label: "Canvas", icon: "square.resize", colour: .blue)
                    statBadge(value: "\(dataset.configuration.cutsPerImage)", label: "Cuts/image", icon: "scissors", colour: .orange)
                    statBadge(value: dataset.configuration.pieceFill.rawValue, label: "Fill", icon: "paintbrush", colour: .teal)
                }

                // Split breakdown with visual bars
                GroupBox("Split Breakdown") {
                    VStack(spacing: 16) {
                        ForEach(DatasetSplit.allCases, id: \.rawValue) { split in
                            splitBreakdownRow(split)
                        }
                    }
                    .padding(8)
                }

                // Sample pair previews
                if !samplePairs.isEmpty {
                    samplePairsSection
                }

                // Config details
                GroupBox("Generation Config") {
                    VStack(spacing: 6) {
                        configRow("Piece size", value: "\(dataset.configuration.pieceSize) px")
                        configRow("Grid", value: "1 x 2")
                        Divider()
                        configRow("Correct (requested)", value: "\(dataset.configuration.correctCount)")
                        configRow("Shape match (requested)", value: "\(dataset.configuration.wrongShapeMatchCount)")
                        configRow("Image match (requested)", value: "\(dataset.configuration.wrongImageMatchCount)")
                        configRow("Nothing (requested)", value: "\(dataset.configuration.wrongNothingCount)")
                        Divider()
                        configRow("Train ratio", value: String(format: "%.0f%%", dataset.configuration.trainRatio * 100))
                        configRow("Test ratio", value: String(format: "%.0f%%", dataset.configuration.testRatio * 100))
                        configRow("Valid ratio", value: String(format: "%.0f%%", dataset.configuration.validRatio * 100))
                    }
                    .padding(8)
                }

                // Actions
                HStack(spacing: 12) {
                    Button {
                        exportDataset()
                    } label: {
                        Label("Export...", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        datasetState.deleteDataset(dataset)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .task(id: dataset.id) {
            samplePairs = loadSamplePairs()
        }
    }

    // MARK: - Stat Badge

    private func statBadge(value: String, label: String, icon: String, colour: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(colour)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 70)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(colour.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Split Breakdown

    private func splitBreakdownRow(_ split: DatasetSplit) -> some View {
        let catCounts = dataset.splitCounts[split] ?? [:]
        let splitTotal = catCounts.values.reduce(0, +)
        let maxCount = dataset.totalPairs > 0 ? dataset.totalPairs : 1

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(split.rawValue.capitalized)
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(splitTotal) pairs")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(DatasetCategory.allCases, id: \.rawValue) { category in
                        let count = catCounts[category] ?? 0
                        let width = maxCount > 0 ? geo.size.width * CGFloat(count) / CGFloat(maxCount) : 0
                        Rectangle()
                            .fill(categoryColour(category))
                            .frame(width: max(width, count > 0 ? 2 : 0))
                            .help("\(category.displayName): \(count)")
                    }
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Category counts
            HStack(spacing: 12) {
                ForEach(DatasetCategory.allCases, id: \.rawValue) { category in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(categoryColour(category))
                            .frame(width: 8, height: 8)
                        Text("\(category.displayName): \(catCounts[category] ?? 0)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func categoryColour(_ category: DatasetCategory) -> Color {
        switch category {
        case .correct: return .green
        case .wrongShapeMatch: return .orange
        case .wrongImageMatch: return .blue
        case .wrongNothing: return .red
        }
    }

    // MARK: - Sample Pairs

    private var samplePairsSection: some View {
        GroupBox("Sample Pairs") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                ForEach(samplePairs, id: \.id) { pair in
                    SamplePairCard(pair: pair)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Config

    private func configRow(_ label: String, value: String) -> some View {
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

    // MARK: - Sample Loading

    private func loadSamplePairs() -> [SamplePair] {
        let datasetDir = DatasetStore.datasetDirectory(for: dataset.id)
        let fm = FileManager.default
        var pairs: [SamplePair] = []

        // Load up to 2 samples per category from the train split
        for category in DatasetCategory.allCases {
            let catDir = datasetDir
                .appendingPathComponent("train")
                .appendingPathComponent(category.rawValue)
            guard fm.fileExists(atPath: catDir.path) else { continue }

            // Find pair files
            guard let files = try? fm.contentsOfDirectory(at: catDir, includingPropertiesForKeys: nil)
                .filter({ $0.lastPathComponent.hasSuffix("_left.png") })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            else { continue }

            for leftFile in files.prefix(2) {
                let rightFile = catDir.appendingPathComponent(
                    leftFile.lastPathComponent.replacingOccurrences(of: "_left.png", with: "_right.png")
                )
                guard fm.fileExists(atPath: rightFile.path),
                      let leftImage = NSImage(contentsOf: leftFile),
                      let rightImage = NSImage(contentsOf: rightFile) else { continue }

                pairs.append(SamplePair(
                    category: category,
                    leftImage: leftImage,
                    rightImage: rightImage,
                    filename: leftFile.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "_left", with: "")
                ))
            }
        }

        return pairs
    }

    // MARK: - Actions

    private func exportDataset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export the dataset"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DatasetStore.exportDataset(dataset, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

// MARK: - Sample Pair Model

private struct SamplePair: Identifiable {
    let id = UUID()
    let category: DatasetCategory
    let leftImage: NSImage
    let rightImage: NSImage
    let filename: String
}

// MARK: - Sample Pair Card

private struct SamplePairCard: View {
    let pair: SamplePair

    var body: some View {
        VStack(spacing: 8) {
            // Side-by-side pieces
            HStack(spacing: 4) {
                Image(nsImage: pair.leftImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Image(nsImage: pair.rightImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Label
            HStack(spacing: 6) {
                categoryBadge(pair.category)
                Text(pair.filename)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func categoryBadge(_ category: DatasetCategory) -> some View {
        let colour: Color = switch category {
        case .correct: .green
        case .wrongShapeMatch: .orange
        case .wrongImageMatch: .blue
        case .wrongNothing: .red
        }

        Text(category.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(colour)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colour.opacity(0.12))
            .clipShape(Capsule())
    }
}
