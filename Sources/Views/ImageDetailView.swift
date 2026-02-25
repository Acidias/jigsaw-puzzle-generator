import SwiftUI

struct ImageDetailView: View {
    @ObservedObject var image: PuzzleImage

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Source image preview
                Image(nsImage: image.sourceImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 4)
                    .padding(.horizontal)

                // Image info
                HStack(spacing: 24) {
                    Label("\(image.imageWidth) x \(image.imageHeight) px", systemImage: "ruler")
                    if let url = image.sourceImageURL {
                        Label(url.lastPathComponent, systemImage: "doc")
                    }
                    if !image.cuts.isEmpty {
                        Label("\(image.cuts.count) puzzle\(image.cuts.count == 1 ? "" : "s") generated", systemImage: "puzzlepiece")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()

                // Generate a new puzzle cut
                ConfigurationPanel(image: image)
                    .padding(.horizontal)

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle(image.name)
    }
}
