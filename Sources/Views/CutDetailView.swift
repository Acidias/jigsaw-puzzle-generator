import SwiftUI

/// Overview of a project-level cut - shows all images in a grid with thumbnails and piece counts.
struct CutOverviewView: View {
    @ObservedObject var cut: PuzzleCut
    let project: PuzzleProject
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cut info header
                HStack(spacing: 24) {
                    Label("\(cut.configuration.columns) x \(cut.configuration.rows) grid", systemImage: "grid")
                    Label("\(cut.totalPieceCount) total pieces", systemImage: "puzzlepiece")
                    Label("\(cut.imageResults.count) image\(cut.imageResults.count == 1 ? "" : "s")", systemImage: "photo.stack")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if cut.isGenerating {
                    VStack(spacing: 8) {
                        ProgressView(value: cut.overallProgress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 300)
                        Text("Generating puzzles... \(Int(cut.overallProgress * 100))%")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Image results grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    ForEach(cut.imageResults) { imageResult in
                        CutImageCard(imageResult: imageResult, project: project)
                            .onTapGesture {
                                appState.selectedCutImageID = imageResult.id
                                appState.selectedPieceID = nil
                            }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle(cut.displayName)
    }
}

/// Thumbnail card for one image result within the cut overview grid.
private struct CutImageCard: View {
    @ObservedObject var imageResult: CutImageResult
    let project: PuzzleProject

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail with overlay
            ZStack {
                if let sourceImage = project.images.first(where: { $0.id == imageResult.imageID }) {
                    Image(nsImage: sourceImage.sourceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipped()
                        .overlay {
                            if imageResult.hasGeneratedPieces {
                                PuzzleOverlayView(imageResult: imageResult)
                            }
                        }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 150)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }

                if imageResult.isGenerating {
                    ZStack {
                        Color.black.opacity(0.4)
                        VStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("\(Int(imageResult.progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }

                if let error = imageResult.lastError {
                    ZStack {
                        Color.red.opacity(0.2)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.title2)
                    }
                    .help(error)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Label
            VStack(spacing: 2) {
                Text(imageResult.imageName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if imageResult.hasGeneratedPieces {
                    Text("\(imageResult.pieces.count) pieces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

/// Detailed view for one image's results within a cut - source image with puzzle overlay.
struct CutImageDetailView: View {
    let sourceImage: PuzzleImage
    @ObservedObject var imageResult: CutImageResult
    let configuration: PuzzleConfiguration

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image with puzzle overlay
                ZStack {
                    Image(nsImage: sourceImage.sourceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if imageResult.hasGeneratedPieces {
                                PuzzleOverlayView(imageResult: imageResult)
                            }
                        }

                    if imageResult.isGenerating {
                        ZStack {
                            Color.black.opacity(0.4)
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                                Text("Generating puzzle...")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                ProgressView(value: imageResult.progress)
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .frame(width: 200)
                                Text("\(Int(imageResult.progress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .frame(maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4)
                .padding(.horizontal)

                // Cut info
                HStack(spacing: 24) {
                    Label("\(configuration.columns) x \(configuration.rows) grid", systemImage: "grid")
                    Label("\(imageResult.pieces.count) pieces", systemImage: "puzzlepiece")
                    Label("\(sourceImage.imageWidth) x \(sourceImage.imageHeight) px", systemImage: "ruler")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle("\(sourceImage.name) - \(configuration.columns)x\(configuration.rows)")
    }
}
