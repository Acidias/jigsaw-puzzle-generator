import SwiftUI

/// Small thumbnail card for a source image in the project detail grid.
struct ProjectImageCard: View {
    let image: PuzzleImage
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: image.sourceImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 120)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(spacing: 2) {
                Text(image.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(image.imageWidth) x \(image.imageHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Remove Image") {
                onRemove()
            }
        }
    }
}
