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
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarSection("Batch Processing") {
                    sidebarRow(
                        item: .batchLocal,
                        label: "Local Images",
                        icon: "folder"
                    )
                    sidebarRow(
                        item: .batchOpenverse,
                        label: "Openverse",
                        icon: "globe"
                    )
                }

                sidebarSection("Projects") {
                    ForEach(appState.projects) { project in
                        ProjectRow(
                            project: project,
                            selection: $selection,
                            onSelect: { handleSelection($0) }
                        )
                        .contextMenu {
                            Button("Remove") {
                                appState.removeProject(project)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
        }
        .background(.ultraThinMaterial)
        .onChange(of: selection) { _, newValue in
            handleSelection(newValue)
        }
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 4)

            content()
        }
    }

    @ViewBuilder
    private func sidebarRow(
        item: SidebarItem,
        label: String,
        icon: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
            Text(label)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selection == item
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = item
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
    @Binding var selection: SidebarItem?
    var onSelect: (SidebarItem?) -> Void

    @State private var isExpanded = false

    private var isProjectSelected: Bool {
        selection == .project(project.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header row
            HStack(spacing: 6) {
                // Disclosure arrow
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
                    .onTapGesture {
                        isExpanded.toggle()
                    }

                Image(systemName: "photo")
                    .foregroundStyle(.blue)
                    .frame(width: 16)

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

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isProjectSelected
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture {
                selection = .project(project.id)
                onSelect(.project(project.id))
                if !isExpanded {
                    isExpanded = true
                }
            }

            // Expanded children
            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    if project.hasGeneratedPieces {
                        ForEach(project.pieces) { piece in
                            pieceRow(piece)
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
                        .padding(.leading, 30)
                        .padding(.vertical, 3)
                    } else {
                        Text("No pieces generated yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.leading, 30)
                            .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pieceRow(_ piece: PuzzlePiece) -> some View {
        let isSelected = selection == .piece(piece.id)

        HStack(spacing: 8) {
            pieceTypeIcon(piece.pieceType)
            Text(piece.displayLabel)
                .font(.callout)
            Spacer()
        }
        .padding(.leading, 30)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .piece(piece.id)
            onSelect(.piece(piece.id))
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
