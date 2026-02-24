import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let project = appState.selectedProject {
                if let piece = appState.selectedPiece {
                    PieceDetailView(project: project, piece: piece)
                } else {
                    ImageDetailView(project: project)
                }
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    importImage()
                } label: {
                    Label("Import Image", systemImage: "photo.badge.plus")
                }
                .keyboardShortcut("o", modifiers: .command)

                if let project = appState.selectedProject, project.hasGeneratedPieces {
                    Button {
                        exportAll()
                    } label: {
                        Label("Export All", systemImage: "square.and.arrow.up")
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
        }
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image to create a jigsaw puzzle from"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else { return }

        let name = url.deletingPathExtension().lastPathComponent
        let project = PuzzleProject(name: name, sourceImage: image, sourceImageURL: url)
        appState.addProject(project)
    }

    private func exportAll() {
        guard let project = appState.selectedProject, project.hasGeneratedPieces else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export puzzle pieces"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await ExportService.export(project: project, to: url)
        }
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Jigsaw Puzzle Generator")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Import an image to get started")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Press \u{2318}O to open an image file")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
