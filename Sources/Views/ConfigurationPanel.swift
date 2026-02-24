import SwiftUI

struct ConfigurationPanel: View {
    @ObservedObject var project: PuzzleProject
    @EnvironmentObject var appState: AppState

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
                                in: 3...100,
                                step: 1
                            )
                            Stepper(
                                "",
                                value: $project.configuration.columns,
                                in: 3...100
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
                                in: 3...100,
                                step: 1
                            )
                            Stepper(
                                "",
                                value: $project.configuration.rows,
                                in: 3...100
                            )
                            .labelsHidden()
                        }
                    }
                }

                // Summary and generate button
                HStack {
                    Text("\(project.configuration.totalPieces) pieces total")
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
                    .disabled(project.isGenerating)
                }
            }
            .padding(8)
        }
    }

    private func generatePuzzle() {
        guard !project.isGenerating else { return }

        Task {
            project.isGenerating = true
            project.progress = 0.0
            project.pieces = []
            project.linesImage = nil
            appState.selectedPieceID = nil

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

            if let result = result {
                project.pieces = result.pieces
                project.linesImage = result.linesImage
            }
            project.isGenerating = false
            project.progress = 1.0
        }
    }
}
