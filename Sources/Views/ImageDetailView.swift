import SwiftUI

struct ImageDetailView: View {
    @ObservedObject var project: PuzzleProject

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image preview with puzzle overlay
                ZStack {
                    Image(nsImage: project.sourceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if project.hasGeneratedPieces {
                                PuzzleOverlayView(project: project)
                            }
                        }

                    // Generation overlay with progress
                    if project.isGenerating {
                        ZStack {
                            Color.black.opacity(0.4)
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                                Text("Generating puzzle...")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                ProgressView(value: project.progress)
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .frame(width: 200)
                                Text("\(Int(project.progress * 100))%")
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

                // Image info
                HStack(spacing: 24) {
                    Label("\(project.imageWidth) x \(project.imageHeight) px", systemImage: "ruler")
                    if let url = project.sourceImageURL {
                        Label(url.lastPathComponent, systemImage: "doc")
                    }
                    if project.hasGeneratedPieces {
                        Label("\(project.pieces.count) pieces", systemImage: "puzzlepiece")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()

                // Configuration panel
                ConfigurationPanel(project: project)
                    .padding(.horizontal)

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle(project.name)
    }
}
