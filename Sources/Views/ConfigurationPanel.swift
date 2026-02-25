import SwiftUI

struct ConfigurationPanel: View {
    @ObservedObject var image: PuzzleImage
    @EnvironmentObject var appState: AppState

    @State private var showErrorAlert = false

    var body: some View {
        GroupBox("Puzzle Configuration") {
            VStack(spacing: 16) {
                // Grid size controls
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Columns: \(image.configuration.columns)")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(image.configuration.columns) },
                                    set: { image.configuration.columns = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            Stepper(
                                "",
                                value: $image.configuration.columns,
                                in: 1...100
                            )
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rows: \(image.configuration.rows)")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(image.configuration.rows) },
                                    set: { image.configuration.rows = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            Stepper(
                                "",
                                value: $image.configuration.rows,
                                in: 1...100
                            )
                            .labelsHidden()
                        }
                    }
                }

                // Summary and generate button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if image.hasGeneratedPieces {
                            Text("\(image.pieces.count) pieces generated")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(image.configuration.totalPieces) pieces")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        generatePuzzle()
                    } label: {
                        Label("Generate Puzzle", systemImage: "puzzlepiece.extension.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(image.isGenerating)
                }
            }
            .padding(8)
        }
        .alert("Generation Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(image.lastError ?? "An unknown error occurred.")
        }
    }

    private func generatePuzzle() {
        guard !image.isGenerating else { return }

        Task {
            image.isGenerating = true
            image.progress = 0.0
            image.pieces = []
            image.linesImage = nil
            image.lastError = nil
            appState.selectedPieceID = nil

            // Clean up previous output directory before generating
            image.cleanupOutputDirectory()

            var config = image.configuration
            config.validate()
            image.configuration = config

            let generator = PuzzleGenerator()
            let result = await generator.generate(
                image: image.sourceImage,
                imageURL: image.sourceImageURL,
                configuration: config,
                onProgress: { progress in
                    Task { @MainActor in
                        image.progress = progress
                    }
                }
            )

            switch result {
            case .success(let generation):
                image.pieces = generation.pieces
                image.linesImage = generation.linesImage
                image.outputDirectory = generation.outputDirectory

                // Persist generated pieces and save project
                if let project = appState.projectForImage(id: image.id) {
                    ProjectStore.moveGeneratedPieces(for: image, in: project)
                    ProjectStore.saveLinesOverlay(for: image, in: project)
                    appState.saveProject(project)
                }
            case .failure(let error):
                image.lastError = error.errorDescription
                showErrorAlert = true
            }
            image.isGenerating = false
            image.progress = 1.0
        }
    }
}
