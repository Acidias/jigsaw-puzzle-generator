import SwiftUI

struct PieceDetailView: View {
    @ObservedObject var project: PuzzleProject
    let piece: PuzzlePiece

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Piece image
                if let image = piece.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 400)
                        .background {
                            // Checkerboard pattern to show transparency
                            CheckerboardView()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)
                } else {
                    Image(systemName: "puzzlepiece")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .frame(width: 200, height: 200)
                }

                // Piece info
                GroupBox("Piece Information") {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow("Position", value: "Row \(piece.row), Column \(piece.col)")
                        infoRow("Type", value: piece.pieceType.rawValue.capitalized)
                        Divider()
                        infoRow("Top Edge", value: piece.topEdge.rawValue.capitalized)
                        infoRow("Right Edge", value: piece.rightEdge.rawValue.capitalized)
                        infoRow("Bottom Edge", value: piece.bottomEdge.rawValue.capitalized)
                        infoRow("Left Edge", value: piece.leftEdge.rawValue.capitalized)
                        Divider()
                        infoRow("Neighbours", value: neighbourDescription())
                    }
                    .padding(8)
                }
                .padding(.horizontal)

                // Export single piece button
                Button {
                    exportPiece()
                } label: {
                    Label("Export This Piece", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle(piece.displayLabel)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
    }

    private func neighbourDescription() -> String {
        var parts: [String] = []
        let config = project.configuration

        if piece.row > 0 {
            parts.append("Above: (\(piece.row - 1), \(piece.col))")
        }
        if piece.row < config.rows - 1 {
            parts.append("Below: (\(piece.row + 1), \(piece.col))")
        }
        if piece.col > 0 {
            parts.append("Left: (\(piece.row), \(piece.col - 1))")
        }
        if piece.col < config.columns - 1 {
            parts.append("Right: (\(piece.row), \(piece.col + 1))")
        }

        return parts.joined(separator: ", ")
    }

    private func exportPiece() {
        guard let image = piece.image else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "piece_\(piece.row)_\(piece.col).png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }
    }
}

/// Checkerboard pattern to visualise transparency in piece images.
struct CheckerboardView: View {
    let squareSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))

            for row in 0..<rows {
                for col in 0..<cols {
                    if (row + col).isMultiple(of: 2) {
                        let rect = CGRect(
                            x: CGFloat(col) * squareSize,
                            y: CGFloat(row) * squareSize,
                            width: squareSize,
                            height: squareSize
                        )
                        context.fill(Path(rect), with: .color(.gray.opacity(0.2)))
                    }
                }
            }
        }
    }
}
