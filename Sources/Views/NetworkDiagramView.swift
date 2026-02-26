import SwiftUI

/// Visual flow diagram of a Siamese Neural Network architecture.
/// Updates reactively as the architecture binding changes.
struct NetworkDiagramView: View {
    @Binding var architecture: SiameseArchitecture

    var body: some View {
        VStack(spacing: 0) {
            // Input layer
            HStack(spacing: 40) {
                nodeBox("Input", subtitle: "\(architecture.inputSize)x\(architecture.inputSize)x4", colour: .blue)
                Text("Shared Weights")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                nodeBox("Input", subtitle: "\(architecture.inputSize)x\(architecture.inputSize)x4", colour: .blue)
            }

            connectorLine()

            // Conv blocks
            ForEach(Array(architecture.convBlocks.enumerated()), id: \.element.id) { index, block in
                HStack(spacing: 40) {
                    convNodeBox(block, index: index)
                    Spacer().frame(width: 100)
                    convNodeBox(block, index: index)
                }
                connectorLine()
            }

            // Flatten
            let poolCount = architecture.convBlocks.filter(\.useMaxPool).count
            let spatialDim = max(1, architecture.inputSize / (1 << poolCount))
            let lastFilters = architecture.convBlocks.last?.filters ?? 1
            HStack(spacing: 40) {
                nodeBox("Flatten", subtitle: "\(lastFilters * spatialDim * spatialDim)", colour: .orange)
                Spacer().frame(width: 100)
                nodeBox("Flatten", subtitle: "\(lastFilters * spatialDim * spatialDim)", colour: .orange)
            }

            connectorLine()

            // Embedding
            HStack(spacing: 40) {
                nodeBox("Embedding", subtitle: "\(architecture.embeddingDimension)-d", colour: .teal)
                Spacer().frame(width: 100)
                nodeBox("Embedding", subtitle: "\(architecture.embeddingDimension)-d", colour: .teal)
            }

            // Merge arrows
            mergeArrows()

            // Comparison
            nodeBox(architecture.comparisonMethod.displayName, subtitle: "Compare", colour: .indigo)

            connectorLine()

            // Sigmoid output
            nodeBox("Sigmoid", subtitle: "Match probability", colour: .green)
        }
        .padding()
    }

    // MARK: - Node Components

    private func nodeBox(_ title: String, subtitle: String, colour: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(colour)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(colour.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(colour.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func convNodeBox(_ block: ConvBlock, index: Int) -> some View {
        let parts = [
            "Conv\(index + 1): \(block.filters)f, \(block.kernelSize)x\(block.kernelSize)",
            block.useBatchNorm ? "BN" : nil,
            "ReLU",
            block.useMaxPool ? "MaxPool" : nil,
        ].compactMap { $0 }.joined(separator: " - ")

        return nodeBox("Conv Block \(index + 1)", subtitle: parts, colour: .purple)
    }

    private func connectorLine() -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 16)
    }

    private func mergeArrows() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                    .frame(maxWidth: 80)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 16)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                    .frame(maxWidth: 80)
            }
        }
        .padding(.vertical, 4)
    }
}
