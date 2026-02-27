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
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(result.content.prefix(2000))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: 200)

                    if !result.images.isEmpty {
                        toolResultImages(result.images)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(result.toolName.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !result.images.isEmpty {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("\(result.images.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Image Thumbnails

    private func toolResultImages(_ images: [ToolResultImage]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140))], spacing: 8) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                VStack(spacing: 2) {
                    if let nsImage = base64ToNSImage(image.base64Data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    Text(image.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func base64ToNSImage(_ base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}
