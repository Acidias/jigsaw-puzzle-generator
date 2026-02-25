import SwiftUI

enum SidebarItem: Hashable {
    case batchLocal
    case batchOpenverse
    case project(UUID)
    case image(UUID)
    case piece(UUID)
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Batch Processing") {
                Label("Local Images", systemImage: "folder")
                    .tag(SidebarItem.batchLocal)
                Label("Openverse", systemImage: "globe")
                    .tag(SidebarItem.batchOpenverse)
            }

            Section("Projects") {
                ForEach(appState.projects) { project in
                    ProjectRow(project: project)
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
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
        .onChange(of: selection) { _, newValue in
            handleSelection(newValue)
        }
    }

    private func handleSelection(_ item: SidebarItem?) {
        switch item {
        case .batchLocal, .batchOpenverse:
            appState.selectedProjectID = nil
            appState.selectedImageID = nil
            appState.selectedPieceID = nil

        case .project(let id):
            appState.selectedProjectID = id
            appState.selectedImageID = nil
            appState.selectedPieceID = nil

        case .image(let imageID):
            // Find the project that owns this image
            if let project = appState.projectForImage(id: imageID) {
                appState.selectedProjectID = project.id
                appState.selectedImageID = imageID
                appState.selectedPieceID = nil
            }

        case .piece(let pieceID):
            // Find the image and project that own this piece
            if let result = appState.imageForPiece(id: pieceID) {
                appState.selectedProjectID = result.project.id
                appState.selectedImageID = result.image.id
                appState.selectedPieceID = pieceID
            }

        case nil:
            appState.selectedProjectID = nil
            appState.selectedImageID = nil
            appState.selectedPieceID = nil
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

/// Three-level project row: Project > Images > Pieces.
private struct ProjectRow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var project: PuzzleProject

    var body: some View {
        DisclosureGroup {
            if project.images.isEmpty {
                Text("No images yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(project.images) { image in
                    ImageRow(image: image)
                        .contextMenu {
                            Button("Remove") {
                                appState.removeImage(image, from: project)
                                appState.saveProject(project)
                            }
                        }
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
                    let pieceCount = project.images.reduce(0) { $0 + $1.pieces.count }
                    if imageCount > 0 {
                        Text("\(imageCount) image\(imageCount == 1 ? "" : "s"), \(pieceCount) pieces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tag(SidebarItem.project(project.id))
        }
    }
}

/// Image row within a project, showing pieces underneath.
private struct ImageRow: View {
    @ObservedObject var image: PuzzleImage

    var body: some View {
        DisclosureGroup {
            if image.hasGeneratedPieces {
                ForEach(image.pieces) { piece in
                    HStack(spacing: 8) {
                        pieceTypeIcon(piece.pieceType)
                        Text(piece.displayLabel)
                            .font(.callout)
                    }
                    .tag(SidebarItem.piece(piece.id))
                }
            } else if image.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else {
                Text("No pieces generated yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.name)
                        .fontWeight(.medium)
                    if image.hasGeneratedPieces {
                        Text("\(image.pieces.count) pieces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if image.isGenerating {
                        Text("Generating... \(Int(image.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tag(SidebarItem.image(image.id))
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
