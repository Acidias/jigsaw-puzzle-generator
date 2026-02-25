import SwiftUI

enum SidebarItem: Hashable {
    case batchLocal
    case batchOpenverse
    case project(UUID)
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
            appState.selectedPieceID = nil

        case .project(let id):
            appState.selectedProjectID = id
            appState.selectedPieceID = nil

        case .piece(let pieceID):
            // Find the project that owns this piece
            for project in appState.projects {
                if project.pieces.contains(where: { $0.id == pieceID }) {
                    appState.selectedProjectID = project.id
                    appState.selectedPieceID = pieceID
                    return
                }
            }

        case nil:
            appState.selectedProjectID = nil
            appState.selectedPieceID = nil
        }
    }
}

/// Extracted sub-view so SwiftUI properly observes @Published changes on the project.
private struct ProjectRow: View {
    @ObservedObject var project: PuzzleProject

    var body: some View {
        DisclosureGroup {
            if project.hasGeneratedPieces {
                ForEach(project.pieces) { piece in
                    HStack(spacing: 8) {
                        pieceTypeIcon(piece.pieceType)
                        Text(piece.displayLabel)
                            .font(.callout)
                    }
                    .tag(SidebarItem.piece(piece.id))
                }
            } else if project.isGenerating {
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
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .fontWeight(.medium)
                    if project.hasGeneratedPieces {
                        Text("\(project.pieces.count) pieces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if project.isGenerating {
                        Text("Generating... \(Int(project.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tag(SidebarItem.project(project.id))
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
