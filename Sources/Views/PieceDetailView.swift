import SwiftUI

struct PieceDetailView: View {
    let piece: PuzzlePiece

    @State private var exportError: String?
    @State private var showExportError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Piece image
                if let pieceImage = piece.image {
                    Image(nsImage: pieceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 400)
                        .background {
                            CheckerboardView()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text("Image unavailable")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("The piece image file may have been deleted.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 200, height: 200)
                }

                // Piece info
                GroupBox("Piece Information") {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow("Piece ID", value: "\(piece.pieceIndex)")
                        infoRow("Type", value: piece.pieceType.rawValue.capitalized)
                        Divider()
                        infoRow("Bounding Box", value: "(\(piece.x1), \(piece.y1)) to (\(piece.x2), \(piece.y2))")
                        infoRow("Size", value: "\(piece.pieceWidth) x \(piece.pieceHeight) px")
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
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "An unknown error occurred.")
        }
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
        if piece.neighbourIDs.isEmpty {
            return "None"
        }
        return piece.neighbourIDs.map { "Piece \($0)" }.joined(separator: ", ")
    }

    private func exportPiece() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "piece_\(piece.pieceIndex).png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if let sourcePath = piece.imagePath,
               FileManager.default.fileExists(atPath: sourcePath.path) {
                try FileManager.default.copyItem(at: sourcePath, to: url)
                return
            }

            guard let pieceImage = piece.image,
                  let tiffData = pieceImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                exportError = "The piece image is unavailable. The source file may have been deleted."
                showExportError = true
                return
            }
            try pngData.write(to: url)
        } catch {
            exportError = "Failed to save piece: \(error.localizedDescription)"
            showExportError = true
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
