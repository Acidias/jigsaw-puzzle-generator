import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedPieceID ?? appState.selectedProjectID },
            set: { newValue in
                handleSelection(newValue)
            }
        )) {
            ForEach(appState.projects) { project in
                ProjectRow(project: project)
                    .contextMenu {
                        Button("Remove") {
                            appState.removeProject(project)
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
    }

    private func handleSelection(_ id: UUID?) {
        guard let id = id else {
            appState.selectedProjectID = nil
            appState.selectedPieceID = nil
            return
        }

        // Check if the ID matches a project
        if appState.projects.contains(where: { $0.id == id }) {
            appState.selectedProjectID = id
            appState.selectedPieceID = nil
            return
        }

        // Check if the ID matches a piece in any project
        for project in appState.projects {
            if project.pieces.contains(where: { $0.id == id }) {
                appState.selectedProjectID = project.id
                appState.selectedPieceID = id
                return
            }
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
                    .tag(piece.id)
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
            .tag(project.id)
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
