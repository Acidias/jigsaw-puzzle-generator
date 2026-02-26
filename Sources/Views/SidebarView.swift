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
                            Text(model.status.rawValue.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarItem.model(model.id))
                    .contextMenu {
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
        do {
            try DatasetStore.exportDataset(dataset, to: url)
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
