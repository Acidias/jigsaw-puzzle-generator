import SwiftUI

struct ConfigurationPanel: View {
    @ObservedObject var image: PuzzleImage
    @EnvironmentObject var appState: AppState

    @State private var columns: Int = 5
    @State private var rows: Int = 5
    @State private var showErrorAlert = false
    @State private var errorMessage: String?
    @State private var isGenerating = false

    var body: some View {
        GroupBox("Generate Puzzle") {
            VStack(spacing: 16) {
                // Grid size controls
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Columns: \(columns)")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(columns) },
                                    set: { columns = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            Stepper("", value: $columns, in: 1...100)
                                .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rows: \(rows)")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(rows) },
                                    set: { rows = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            Stepper("", value: $rows, in: 1...100)
                                .labelsHidden()
                        }
                    }
                }

                HStack {
                    Text("\(columns * rows) pieces")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        generatePuzzle()
                    } label: {
                        Label("Generate Puzzle", systemImage: "puzzlepiece.extension.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isGenerating)
                }
            }
            .padding(8)
        }
        .alert("Generation Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func generatePuzzle() {
        guard !isGenerating else { return }

        var config = PuzzleConfiguration(columns: columns, rows: rows)
        config.validate()
        columns = config.columns
        rows = config.rows

        let cut = PuzzleCut(configuration: config)
        image.cuts.append(cut)

        // Select the new cut in the sidebar
        appState.selectedCutID = cut.id
        appState.selectedPieceID = nil

        isGenerating = true

        Task {
            cut.isGenerating = true
            cut.progress = 0.0

            let generator = PuzzleGenerator()
            let result = await generator.generate(
                image: image.sourceImage,
                imageURL: image.sourceImageURL,
                configuration: config,
                onProgress: { progress in
                    Task { @MainActor in
                        cut.progress = progress
                    }
                }
            )

            switch result {
            case .success(let generation):
                cut.pieces = generation.pieces
                cut.linesImage = generation.linesImage
                cut.outputDirectory = generation.outputDirectory

                // Persist
                if let project = appState.projectForImage(id: image.id) {
                    ProjectStore.moveGeneratedPieces(for: cut, imageID: image.id, in: project)
                    ProjectStore.saveLinesOverlay(for: cut, imageID: image.id, in: project)
                    appState.saveProject(project)
                }
            case .failure(let error):
                cut.lastError = error.errorDescription
                errorMessage = error.errorDescription
                showErrorAlert = true
                // Remove the failed cut
                image.cuts.removeAll { $0.id == cut.id }
            }
            cut.isGenerating = false
            cut.progress = 1.0
            isGenerating = false
        }
    }
}
