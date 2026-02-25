import SwiftUI

enum SidebarItem: Hashable {
    case batchLocal
    case batchOpenverse
    case datasetGeneration
    case dataset(UUID)
    case project(UUID)
    case cut(UUID)
    case cutImage(UUID)
    case piece(UUID)
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var datasetState: DatasetState
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
                    .tag(SidebarItem.datasetGeneration)

                ForEach(datasetState.datasets) { dataset in
                    HStack(spacing: 8) {
                        Image(systemName: "brain.filled.head.profile")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dataset.name)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text("\(dataset.totalPairs) pairs")
                                .font(.caption)
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
        case .batchLocal, .batchOpenverse, .datasetGeneration, .dataset:
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
