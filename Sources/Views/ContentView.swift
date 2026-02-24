import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragTargeted = false

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
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .foregroundStyle(.blue)
                    .background(.blue.opacity(0.05))
                    .padding(8)
                    .allowsHitTesting(false)
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
        loadImage(from: url)
    }

    private func loadImage(from url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        let project = PuzzleProject(name: name, sourceImage: image, sourceImageURL: url)
        appState.addProject(project)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // Try loading as a file URL first
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }

                    Task { @MainActor in
                        loadImage(from: url)
                    }
                }
                return true
            }

            // Try loading as image data
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data = data, let image = NSImage(data: data) else { return }
                    Task { @MainActor in
                        let project = PuzzleProject(name: "Dropped Image", sourceImage: image)
                        appState.addProject(project)
                    }
                }
                return true
            }
        }
        return false
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
            Text("Drag and drop an image, or press Cmd+O to open")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
