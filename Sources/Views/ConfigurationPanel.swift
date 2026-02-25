import SwiftUI

struct ConfigurationPanel: View {
    @ObservedObject var project: PuzzleProject
    @EnvironmentObject var appState: AppState

    @State private var showErrorAlert = false

    var body: some View {
        GroupBox("Puzzle Configuration") {
            VStack(spacing: 16) {
                // Grid size controls
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Columns: \(project.configuration.columns)")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(project.configuration.columns) },
                                    set: { project.configuration.columns = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            Stepper(
                                "",
                                value: $project.configuration.columns,
                                in: 1...100
                            )
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rows: \(project.configuration.rows)")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(project.configuration.rows) },
                                    set: { project.configuration.rows = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            Stepper(
                                "",
                                value: $project.configuration.rows,
                                in: 1...100
                            )
                            .labelsHidden()
                        }
                    }
                }

                // Summary and generate button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if project.hasGeneratedPieces {
                            Text("\(project.pieces.count) pieces generated")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("~\(project.configuration.totalPieces) pieces (approximate)")
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
                    .disabled(project.isGenerating)
                }
            }
            .padding(8)
        }
        .alert("Generation Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(project.lastError ?? "An unknown error occurred.")
        }
    }

    private func generatePuzzle() {
        guard !project.isGenerating else { return }

        Task {
            project.isGenerating = true
            project.progress = 0.0
            project.pieces = []
            project.linesImage = nil
            project.lastError = nil
            appState.selectedPieceID = nil

            // Clean up previous output directory before generating
            project.cleanupOutputDirectory()

            var config = project.configuration
            config.validate()
            project.configuration = config

            let generator = PuzzleGenerator()
            let result = await generator.generate(
                image: project.sourceImage,
                imageURL: project.sourceImageURL,
                configuration: config,
                onProgress: { progress in
                    Task { @MainActor in
                        project.progress = progress
                    }
                }
            )

            switch result {
            case .success(let generation):
                project.pieces = generation.pieces
                project.linesImage = generation.linesImage
                project.outputDirectory = generation.outputDirectory
            case .failure(let error):
                project.lastError = error.errorDescription
                showErrorAlert = true
            }
            project.isGenerating = false
            project.progress = 1.0
        }
    }
}
