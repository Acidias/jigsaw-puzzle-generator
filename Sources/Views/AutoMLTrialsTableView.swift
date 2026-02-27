import SwiftUI

/// Reusable table displaying AutoML trial results.
/// Used in both AutoMLStudyDetailView and AutoMLPanel.
struct AutoMLTrialsTableView: View {
    let trials: [AutoMLTrial]
    let bestTrialNumber: Int?
    let searchDimensions: [SearchDimension]

    @State private var sortByValue = true

    var body: some View {
        if trials.isEmpty {
            Text("No trials yet")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text("Trials (\(trials.count))")
                        .font(.headline)
                    Spacer()
                    Button(sortByValue ? "Sorted by Value" : "Sorted by #") {
                        sortByValue.toggle()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                // Table header
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: 30, alignment: .leading)
                    Text("State")
                        .frame(width: 70, alignment: .leading)
                    Text("Value")
                        .frame(width: 80, alignment: .trailing)

                    // Dynamic param columns
                    ForEach(searchDimensions) { dim in
                        Text(dim.param.displayName)
                            .frame(width: 80, alignment: .trailing)
                    }

                    Text("Duration")
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                Divider()

                // Rows
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sortedTrials) { trial in
                            trialRow(trial)
                        }
                    }
                }
            }
        }
    }

    private var sortedTrials: [AutoMLTrial] {
        if sortByValue {
            return trials.sorted { a, b in
                let va = a.value ?? -Double.infinity
                let vb = b.value ?? -Double.infinity
                return va > vb
            }
        } else {
            return trials.sorted { $0.trialNumber < $1.trialNumber }
        }
    }

    private func trialRow(_ trial: AutoMLTrial) -> some View {
        let isBest = trial.trialNumber == bestTrialNumber

        return HStack(spacing: 0) {
            HStack(spacing: 2) {
                if isBest {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                }
                Text("\(trial.trialNumber)")
            }
            .frame(width: 30, alignment: .leading)

            HStack(spacing: 4) {
                Circle()
                    .fill(stateColour(trial.state))
                    .frame(width: 8, height: 8)
                Text(trial.state.rawValue)
            }
            .frame(width: 70, alignment: .leading)

            Text(trial.value.map { String(format: "%.4f", $0) } ?? "-")
                .frame(width: 80, alignment: .trailing)

            // Dynamic param values
            ForEach(searchDimensions) { dim in
                Text(trial.params[dim.param.rawValue] ?? "-")
                    .frame(width: 80, alignment: .trailing)
            }

            Text(trial.duration.map { formatDuration($0) } ?? "-")
                .frame(width: 70, alignment: .trailing)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isBest ? Color.green.opacity(0.1) : trial.state == .pruned ? Color.orange.opacity(0.05) : Color.clear)
        )
        .opacity(trial.state == .pruned ? 0.6 : 1.0)
    }

    private func stateColour(_ state: TrialState) -> Color {
        switch state {
        case .complete: return .green
        case .pruned: return .orange
        case .fail: return .red
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            return String(format: "%.1fm", seconds / 60)
        } else {
            return String(format: "%.1fh", seconds / 3600)
        }
    }
}
