import SwiftUI

struct ConfigurationPanel: View {
    @ObservedObject var project: PuzzleProject
    @EnvironmentObject var appState: AppState

    @State private var columns: Int = 5
    @State private var rows: Int = 5
    @State private var normalise = false
    @State private var pieceSize: Int = 224
    @State private var pieceFill: PieceFill = .none
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

                // Normalisation controls
                Divider()

                Toggle("Normalise for AI", isOn: $normalise)
                    .font(.callout)
                    .fontWeight(.medium)

                if normalise {
                    HStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Text("Piece size:")
                                .font(.callout)
                            TextField(
                                "224",
                                value: $pieceSize,
                                format: .number
                            )
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            Stepper("", value: $pieceSize, in: 32...1024, step: 16)
                                .labelsHidden()
                            Text("px")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Picker("Fill:", selection: $pieceFill) {
                            Text("None (transparent)").tag(PieceFill.none)
                            Text("Black").tag(PieceFill.black)
                            Text("White").tag(PieceFill.white)
                            Text("Average grey").tag(PieceFill.grey)
                        }
                        .font(.callout)
                        .frame(maxWidth: 220)
                    }

                    let canvasSize = Int(ceil(Double(pieceSize) * 1.75))
                    Text("Source: \(columns * pieceSize) x \(rows * pieceSize) px - Pieces: \(canvasSize) x \(canvasSize) px each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("\(columns * rows) pieces per image, \(project.images.count) image\(project.images.count == 1 ? "" : "s")")
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
                    .disabled(isGenerating || project.images.isEmpty)
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
        guard !isGenerating, !project.images.isEmpty else { return }

        var config = PuzzleConfiguration(
            columns: columns,
            rows: rows,
            pieceSize: normalise ? pieceSize : nil,
            pieceFill: normalise ? pieceFill : .none
        )
        config.validate()
        columns = config.columns
        rows = config.rows
        if let size = config.pieceSize {
            pieceSize = size
        }

        let cut = PuzzleCut(configuration: config)

        // Create a CutImageResult for each image in the project
        for image in project.images {
            let imageResult = CutImageResult(imageID: image.id, imageName: image.name)
            cut.imageResults.append(imageResult)
        }

        project.cuts.append(cut)

        // Select the new cut in the sidebar
        appState.selectedCutID = cut.id
        appState.selectedCutImageID = nil
        appState.selectedPieceID = nil

        isGenerating = true

        Task {
            for imageResult in cut.imageResults {
                guard let sourceImage = appState.sourceImage(for: imageResult, in: project) else {
                    imageResult.lastError = "Source image not found"
                    continue
                }

                imageResult.isGenerating = true
                imageResult.progress = 0.0

                let generator = PuzzleGenerator()
                let result = await generator.generate(
                    image: sourceImage.sourceImage,
                    imageURL: sourceImage.sourceImageURL,
                    configuration: config,
                    onProgress: { progress in
                        Task { @MainActor in
                            imageResult.progress = progress
                        }
                    }
                )

                switch result {
                case .success(let generation):
                    imageResult.pieces = generation.pieces
                    imageResult.linesImage = generation.linesImage
                    imageResult.outputDirectory = generation.outputDirectory

                    // Persist
                    ProjectStore.moveGeneratedPieces(for: imageResult, cutID: cut.id, in: project)
                    ProjectStore.saveLinesOverlay(for: imageResult, cutID: cut.id, in: project)
                    appState.saveProject(project)

                case .failure(let error):
                    imageResult.lastError = error.errorDescription
                }

                imageResult.isGenerating = false
                imageResult.progress = 1.0
            }

            // Show error if all images failed
            let allFailed = cut.imageResults.allSatisfy { $0.lastError != nil }
            if allFailed {
                errorMessage = "All images failed to generate. Check the sidebar for details."
                showErrorAlert = true
                // Remove the failed cut
                project.cuts.removeAll { $0.id == cut.id }
            }

            isGenerating = false
        }
    }
}
