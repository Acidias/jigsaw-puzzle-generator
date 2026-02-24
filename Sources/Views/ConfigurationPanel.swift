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

                // Tab size and seed
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tab Size: \(Int(project.configuration.tabSize * 100))%")
                            .font(.callout)
                            .fontWeight(.medium)
                        Slider(
                            value: $project.configuration.tabSize,
                            in: 0.20...0.45,
                            step: 0.01
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Seed")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            TextField(
                                "Random",
                                value: $project.configuration.seed,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)

                            Button("Randomise") {
                                project.configuration.seed = UInt64.random(in: 1...UInt64.max)
                            }
                            .buttonStyle(.bordered)
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
            appState.selectedPieceID = nil

            var config = project.configuration
            config.validate()
            project.configuration = config

            let generator = PuzzleGenerator()
            let result = await generator.generate(
                image: project.sourceImage,
                configuration: config,
                onProgress: { progress in
                    Task { @MainActor in
                        project.progress = progress
                    }
                }
            )

            project.pieces = result.pieces
            project.generatedSeed = result.seedUsed
            project.isGenerating = false
            project.progress = 1.0
        }
    }
}
