import SwiftUI

/// Displays the jigsaw puzzle cut lines over the original image.
/// The blend mode makes the white background invisible, showing only the cut lines.
struct PuzzleOverlayView: View {
    @ObservedObject var imageResult: CutImageResult

    var body: some View {
        if let linesImage = imageResult.linesImage {
            Image(nsImage: linesImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
    }
}
