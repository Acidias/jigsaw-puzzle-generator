import SwiftUI

/// Shows a specific puzzle cut - the source image with overlay, grid info, and piece count.
struct CutDetailView: View {
    @ObservedObject var image: PuzzleImage
    @ObservedObject var cut: PuzzleCut

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image with puzzle overlay
                ZStack {
                    Image(nsImage: image.sourceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if cut.hasGeneratedPieces {
                                PuzzleOverlayView(cut: cut)
                            }
                        }

                    if cut.isGenerating {
                        ZStack {
                            Color.black.opacity(0.4)
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                                Text("Generating puzzle...")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                ProgressView(value: cut.progress)
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .frame(width: 200)
                                Text("\(Int(cut.progress * 100))%")
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
                    Label("\(cut.configuration.columns) x \(cut.configuration.rows) grid", systemImage: "grid")
                    Label("\(cut.pieces.count) pieces", systemImage: "puzzlepiece")
                    Label("\(image.imageWidth) x \(image.imageHeight) px", systemImage: "ruler")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle("\(image.name) - \(cut.configuration.columns)x\(cut.configuration.rows)")
    }
}
