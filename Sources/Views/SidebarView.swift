import SwiftUI

enum SidebarItem: Hashable {
    case batchLocal
    case batchOpenverse
    case datasetGeneration
    case dataset(UUID)
    case architecturePresets
    case preset(UUID)
    case modelTraining
    case model(UUID)
    case project(UUID)
    case cut(UUID)
    case cutImage(UUID)
    case piece(UUID)
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var datasetState: DatasetState
    @ObservedObject var modelState: ModelState
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Import") {
                Label("Batch Processing", systemImage: "square.stack")
                    .tag(SidebarItem.batchLocal)
                Label("Openverse Search", systemImage: "globe")
                    .tag(SidebarItem.batchOpenverse)
            }

            Section("AI Tools") {
                Label("Dataset Generation", systemImage: "brain")
                    .font(.body)
                    .fontWeight(.semibold)
                    .tag(SidebarItem.datasetGeneration)

                ForEach(datasetState.datasets) { dataset in
                    HStack(spacing: 6) {
                        Image(systemName: "brain.filled.head.profile")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dataset.name)
                                .font(.callout)
                                .lineLimit(1)
                            Text("\(dataset.totalPairs) pairs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarItem.dataset(dataset.id))
                    .contextMenu {
                        Button("Rename...") {
                            promptRenameDataset(dataset)
                        }
                        Button("Export...") {
                            exportDataset(dataset)
                        }
                        Divider()
                        Button("Delete") {
                            datasetState.deleteDataset(dataset)
                            if case .dataset(dataset.id) = selection {
                                selection = .datasetGeneration
                            }
                        }
                    }
                }

                Label("Architecture Presets", systemImage: "rectangle.3.group")
                    .font(.body)
                    .fontWeight(.semibold)
                    .tag(SidebarItem.architecturePresets)

                ForEach(modelState.presets) { preset in
                    HStack(spacing: 6) {
                        Image(systemName: preset.isBuiltIn ? "lock.rectangle.stack" : "rectangle.stack")
                            .font(.caption)
                            .foregroundStyle(preset.isBuiltIn ? .orange : .teal)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.name)
                                .font(.callout)
                                .lineLimit(1)
                            Text("\(preset.architecture.convBlocks.count) blocks, \(preset.architecture.embeddingDimension)-d")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarItem.preset(preset.id))
                    .contextMenu {
                        Button("Rename...") {
                            promptRenamePreset(preset)
                        }
                        Button("Duplicate") {
                            let copy = modelState.duplicatePreset(preset)
                            selection = .preset(copy.id)
                        }
                        Divider()
                        Button("Delete") {
                            modelState.deletePreset(preset)
                            if case .preset(preset.id) = selection {
                                selection = .architecturePresets
                            }
                        }
                    }
                }

                Label("Model Training", systemImage: "network")
                    .font(.body)
                    .fontWeight(.semibold)
                    .tag(SidebarItem.modelTraining)

                ForEach(modelState.models) { model in
                    HStack(spacing: 6) {
                        Image(systemName: modelStatusIcon(model.status))
                            .font(.caption)
                            .foregroundStyle(modelStatusColour(model.status))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name)
                                .font(.callout)
                                .lineLimit(1)
                            if model.status == .trained, let acc = model.metrics?.testAccuracy {
                                Text("Trained - \(String(format: "%.1f%%", acc * 100))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(model.status.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        modelMenu(model)
                    }
                    .tag(SidebarItem.model(model.id))
                    .contextMenu {
                        modelMenuItems(model)
                    }
                }
            }

            Section("Projects") {
                ForEach(appState.projects) { project in
                    ProjectRow(project: project)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
        .onChange(of: selection) { _, newValue in
            handleSelection(newValue)
        }
    }

    private func handleSelection(_ item: SidebarItem?) {
        switch item {
        case .batchLocal, .batchOpenverse, .datasetGeneration, .dataset, .architecturePresets, .preset, .modelTraining, .model:
            appState.selectedProjectID = nil
            appState.selectedCutID = nil
            appState.selectedCutImageID = nil
            appState.selectedPieceID = nil

        case .project(let id):
            appState.selectedProjectID = id
            appState.selectedCutID = nil
            appState.selectedCutImageID = nil
            appState.selectedPieceID = nil

        case .cut(let cutID):
            if let project = appState.projectForCut(id: cutID) {
                appState.selectedProjectID = project.id
                appState.selectedCutID = cutID
                appState.selectedCutImageID = nil
                appState.selectedPieceID = nil
            }

        case .cutImage(let cutImageID):
            if let result = appState.cutForCutImage(id: cutImageID) {
                appState.selectedProjectID = result.project.id
                appState.selectedCutID = result.cut.id
                appState.selectedCutImageID = cutImageID
                appState.selectedPieceID = nil
            }

        case .piece(let pieceID):
            if let result = appState.cutImageForPiece(id: pieceID) {
                appState.selectedProjectID = result.project.id
                appState.selectedCutID = result.cut.id
                appState.selectedCutImageID = result.imageResult.id
                appState.selectedPieceID = pieceID
            }

        case nil:
            appState.selectedProjectID = nil
            appState.selectedCutID = nil
            appState.selectedCutImageID = nil
            appState.selectedPieceID = nil
        }
    }

    private func promptRenameDataset(_ dataset: PuzzleDataset) {
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

    private func exportDataset(_ dataset: PuzzleDataset) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export the dataset"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let exportDir = url.appendingPathComponent(dataset.name.sanitisedForFilename())
        do {
            try DatasetStore.exportDataset(dataset, to: exportDir)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func modelStatusIcon(_ status: ModelStatus) -> String {
        switch status {
        case .designed: return "circle.dashed"
        case .exported: return "arrow.up.circle"
        case .training: return "play.circle.fill"
        case .trained: return "checkmark.circle.fill"
        }
    }

    private func modelStatusColour(_ status: ModelStatus) -> Color {
        switch status {
        case .designed: return .blue
        case .exported: return .orange
        case .training: return .yellow
        case .trained: return .green
        }
    }

    private func promptRenameModel(_ model: SiameseModel) {
        let alert = NSAlert()
        alert.messageText = "Rename Model"
        alert.informativeText = "Enter a new name for the model."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = model.name
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty {
                model.name = newName
                ModelStore.saveModel(model)
            }
        }
    }

    // MARK: - Model Menu

    private func modelMenu(_ model: SiameseModel) -> some View {
        Menu {
            modelMenuItems(model)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
    }

    @ViewBuilder
    private func modelMenuItems(_ model: SiameseModel) -> some View {
        Button("Export Training Package...") {
            exportTrainingPackage(model)
        }

        if model.status == .trained {
            Button("Export with Results...") {
                exportModelWithResults(model)
            }
        }

        Divider()

        Button("Rename...") {
            promptRenameModel(model)
        }

        Divider()

        Button("Delete") {
            modelState.deleteModel(model)
            if case .model(model.id) = selection {
                selection = .modelTraining
            }
        }
    }

    private func exportTrainingPackage(_ model: SiameseModel) {
        guard let dataset = datasetState.datasets.first(where: { $0.id == model.sourceDatasetID }) else {
            let alert = NSAlert()
            alert.messageText = "Dataset Not Found"
            alert.informativeText = "The source dataset \"\(model.sourceDatasetName)\" is no longer available. Export requires the original dataset."
            alert.runModal()
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export the training package"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let exportDir = url.appendingPathComponent(model.name.sanitisedForFilename())
        do {
            try TrainingScriptGenerator.exportTrainingPackage(
                model: model,
                dataset: dataset,
                to: exportDir
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

    private func exportModelWithResults(_ model: SiameseModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export the model with results"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exportDir = url.appendingPathComponent(model.name.sanitisedForFilename())
        let modelDir = ModelStore.modelDirectory(for: model.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

            // Build and write comprehensive training report
            let report = buildTrainingReport(model: model)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let reportData = try encoder.encode(report)
            let reportDest = exportDir.appendingPathComponent("training_report.json")
            if fm.fileExists(atPath: reportDest.path) {
                try fm.removeItem(at: reportDest)
            }
            try reportData.write(to: reportDest)

            // Copy raw metrics.json if present
            let metricsSource = modelDir.appendingPathComponent("metrics.json")
            if fm.fileExists(atPath: metricsSource.path) {
                let metricsDest = exportDir.appendingPathComponent("metrics.json")
                if fm.fileExists(atPath: metricsDest.path) {
                    try fm.removeItem(at: metricsDest)
                }
                try fm.copyItem(at: metricsSource, to: metricsDest)
            }

            // Copy model.mlpackage directory if present
            let mlpackageSource = ModelStore.coreMLModelPath(for: model.id)
            if fm.fileExists(atPath: mlpackageSource.path) {
                let mlpackageDest = exportDir.appendingPathComponent("model.mlpackage")
                if fm.fileExists(atPath: mlpackageDest.path) {
                    try fm.removeItem(at: mlpackageDest)
                }
                try fm.copyItem(at: mlpackageSource, to: mlpackageDest)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - Training Report

    private func buildTrainingReport(model: SiameseModel) -> TrainingReport {
        let dataset = datasetState.datasets.first { $0.id == model.sourceDatasetID }

        let modelSection = TrainingReport.ModelSection(
            id: model.id.uuidString,
            name: model.name,
            createdAt: model.createdAt,
            status: model.status.rawValue
        )

        let arch = model.architecture
        let archSection = TrainingReport.ArchitectureSection(
            convBlocks: arch.convBlocks.map { block in
                TrainingReport.ConvBlockInfo(
                    filters: block.filters,
                    kernelSize: block.kernelSize,
                    useBatchNorm: block.useBatchNorm,
                    useMaxPool: block.useMaxPool
                )
            },
            embeddingDimension: arch.embeddingDimension,
            comparisonMethod: arch.comparisonMethod.rawValue,
            dropout: arch.dropout,
            learningRate: arch.learningRate,
            batchSize: arch.batchSize,
            epochs: arch.epochs,
            inputSize: arch.inputSize,
            devicePreference: arch.devicePreference.rawValue,
            flattenedSize: arch.flattenedSize
        )

        var datasetSection: TrainingReport.DatasetSection? = nil
        if let ds = dataset {
            let cfg = ds.configuration
            var requestedCounts: [String: Int] = [:]
            for cat in DatasetCategory.allCases {
                requestedCounts[cat.rawValue] = cfg.count(for: cat)
            }

            var actualSplitCounts: [String: [String: Int]] = [:]
            for (split, catCounts) in ds.splitCounts {
                var catDict: [String: Int] = [:]
                for (cat, count) in catCounts {
                    catDict[cat.rawValue] = count
                }
                actualSplitCounts[split.rawValue] = catDict
            }

            datasetSection = TrainingReport.DatasetSection(
                id: ds.id.uuidString,
                name: ds.name,
                sourceProjectName: ds.sourceProjectName,
                rows: cfg.rows,
                columns: cfg.columns,
                pieceSize: cfg.pieceSize,
                pieceFill: cfg.pieceFill.rawValue,
                cutsPerImage: cfg.cutsPerImage,
                trainRatio: cfg.trainRatio,
                testRatio: cfg.testRatio,
                validRatio: cfg.validRatio,
                requestedCounts: requestedCounts,
                actualSplitCounts: actualSplitCounts,
                totalPairs: ds.totalPairs
            )
        }

        var resultsSection: TrainingReport.ResultsSection? = nil
        if let metrics = model.metrics {
            let epochHistory = (0..<metrics.trainLoss.count).map { i in
                TrainingReport.EpochEntry(
                    epoch: metrics.trainLoss[i].epoch,
                    trainLoss: metrics.trainLoss[i].value,
                    validLoss: i < metrics.validLoss.count ? metrics.validLoss[i].value : nil,
                    trainAccuracy: i < metrics.trainAccuracy.count ? metrics.trainAccuracy[i].value : nil,
                    validAccuracy: i < metrics.validAccuracy.count ? metrics.validAccuracy[i].value : nil
                )
            }

            resultsSection = TrainingReport.ResultsSection(
                bestEpoch: metrics.bestEpoch,
                trainingDurationSeconds: metrics.trainingDurationSeconds,
                testAccuracy: metrics.testAccuracy,
                testLoss: metrics.testLoss,
                testPrecision: metrics.testPrecision,
                testRecall: metrics.testRecall,
                testF1: metrics.testF1,
                confusionMatrix: metrics.confusionMatrix,
                perCategoryResults: metrics.perCategoryResults,
                epochHistory: epochHistory
            )
        }

        return TrainingReport(
            model: modelSection,
            architecture: archSection,
            dataset: datasetSection,
            results: resultsSection
        )
    }

    private func promptRenamePreset(_ preset: ArchitecturePreset) {
        let alert = NSAlert()
        alert.messageText = "Rename Preset"
        alert.informativeText = "Enter a new name for the preset."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = preset.name
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty {
                preset.name = newName
                ArchitecturePresetStore.savePreset(preset)
            }
        }
    }
}

// MARK: - Training Report DTO

/// Self-contained training report combining model, architecture, dataset, and results.
/// Exported as training_report.json for external analysis.
private struct TrainingReport: Codable {
    let model: ModelSection
    let architecture: ArchitectureSection
    let dataset: DatasetSection?
    let results: ResultsSection?

    struct ModelSection: Codable {
        let id: String
        let name: String
        let createdAt: Date
        let status: String
    }

    struct ConvBlockInfo: Codable {
        let filters: Int
        let kernelSize: Int
        let useBatchNorm: Bool
        let useMaxPool: Bool
    }

    struct ArchitectureSection: Codable {
        let convBlocks: [ConvBlockInfo]
        let embeddingDimension: Int
        let comparisonMethod: String
        let dropout: Double
        let learningRate: Double
        let batchSize: Int
        let epochs: Int
        let inputSize: Int
        let devicePreference: String
        let flattenedSize: Int
    }

    struct DatasetSection: Codable {
        let id: String
        let name: String
        let sourceProjectName: String
        let rows: Int
        let columns: Int
        let pieceSize: Int
        let pieceFill: String
        let cutsPerImage: Int
        let trainRatio: Double
        let testRatio: Double
        let validRatio: Double
        let requestedCounts: [String: Int]
        let actualSplitCounts: [String: [String: Int]]
        let totalPairs: Int
    }

    struct EpochEntry: Codable {
        let epoch: Int
        let trainLoss: Double
        let validLoss: Double?
        let trainAccuracy: Double?
        let validAccuracy: Double?
    }

    struct ResultsSection: Codable {
        let bestEpoch: Int?
        let trainingDurationSeconds: Double?
        let testAccuracy: Double?
        let testLoss: Double?
        let testPrecision: Double?
        let testRecall: Double?
        let testF1: Double?
        let confusionMatrix: ConfusionMatrix?
        let perCategoryResults: [String: CategoryResult]?
        let epochHistory: [EpochEntry]
    }
}

/// Project row: Project > Cuts > CutImageResults > Pieces.
private struct ProjectRow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var project: PuzzleProject

    var body: some View {
        DisclosureGroup {
            if project.cuts.isEmpty {
                Text("No puzzles generated yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(project.cuts) { cut in
                    CutRow(cut: cut, project: project)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .fontWeight(.medium)
                    let imageCount = project.images.count
                    if imageCount > 0 {
                        Text("\(imageCount) image\(imageCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tag(SidebarItem.project(project.id))
            .contextMenu {
                Button("Rename...") {
                    promptRenameProject(project)
                }
                Divider()
                Button("Remove") {
                    appState.removeProject(project)
                }
            }
        }
    }

    private func promptRenameProject(_ project: PuzzleProject) {
        let alert = NSAlert()
        alert.messageText = "Rename Project"
        alert.informativeText = "Enter a new name for the project."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = project.name
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty {
                project.name = newName
                appState.saveProject(project)
            }
        }
    }
}

/// Cut row showing image results underneath.
private struct CutRow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var cut: PuzzleCut
    @ObservedObject var project: PuzzleProject

    var body: some View {
        DisclosureGroup {
            if cut.imageResults.isEmpty {
                Text("No images processed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(cut.imageResults) { imageResult in
                    CutImageRow(imageResult: imageResult)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(.purple)
                Text(cut.displayName)
                    .fontWeight(.medium)
                if cut.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .tag(SidebarItem.cut(cut.id))
            .contextMenu {
                Button("Remove") {
                    ProjectStore.deleteCut(projectID: project.id, cutID: cut.id)
                    project.cuts.removeAll { $0.id == cut.id }
                    appState.saveProject(project)
                    if appState.selectedCutID == cut.id {
                        appState.selectedCutID = nil
                        appState.selectedCutImageID = nil
                        appState.selectedPieceID = nil
                    }
                }
            }
        }
    }
}

/// CutImageResult row showing pieces underneath.
private struct CutImageRow: View {
    @ObservedObject var imageResult: CutImageResult

    var body: some View {
        DisclosureGroup {
            if imageResult.hasGeneratedPieces {
                ForEach(imageResult.pieces) { piece in
                    HStack(spacing: 8) {
                        pieceTypeIcon(piece.pieceType)
                        Text(piece.displayLabel)
                            .font(.callout)
                    }
                    .tag(SidebarItem.piece(piece.id))
                }
            } else if imageResult.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating... \(Int(imageResult.progress * 100))%")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else if let error = imageResult.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(.teal)
                Text(imageResult.imageName)
                    .fontWeight(.medium)
                if imageResult.hasGeneratedPieces {
                    Text("\(imageResult.pieces.count) pieces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(SidebarItem.cutImage(imageResult.id))
        }
    }

    @ViewBuilder
    private func pieceTypeIcon(_ type: PieceType) -> some View {
        switch type {
        case .corner:
            Image(systemName: "square.bottomtrailing")
                .foregroundStyle(.orange)
        case .edge:
            Image(systemName: "square.trailinghalf.filled")
                .foregroundStyle(.green)
        case .interior:
            Image(systemName: "square.fill")
                .foregroundStyle(.purple)
        }
    }
}
