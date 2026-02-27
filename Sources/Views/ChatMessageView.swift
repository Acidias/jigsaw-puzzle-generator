import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .toolResult:
            toolResultView
        case .toolUse:
            EmptyView()
        }
    }

    // MARK: - User Message

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Assistant Message

    private var assistantBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                }

                if message.isStreaming && message.text.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !message.toolCalls.isEmpty {
                    ForEach(message.toolCalls) { tc in
                        toolCallIndicator(tc)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Tool Call Indicator

    private func toolCallIndicator(_ toolCall: ChatToolCall) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(toolCall.name.replacingOccurrences(of: "_", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Tool Result

    private var toolResultView: some View {
        ForEach(message.toolResults) { result in
            DisclosureGroup {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(result.content.prefix(2000))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 200)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(result.toolName.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }
}
