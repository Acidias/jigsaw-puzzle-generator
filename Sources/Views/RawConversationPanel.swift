import SwiftUI

struct RawConversationPanel: View {
    @ObservedObject var chatState: ChatState

    private var wireMessages: [WireMessage] {
        let provider = chatState.provider
        let rawMessages: [[String: Any]]
        switch provider {
        case .claude:
            // Claude: system prompt is sent separately, not in messages array
            rawMessages = LLMService.buildClaudeMessages(chatState: chatState)
        case .openAI:
            // OpenAI: system prompt is the first message (role: system)
            rawMessages = LLMService.buildOpenAIMessages(chatState: chatState)
        }
        var result: [WireMessage] = []

        // Add system prompt as first entry (Claude sends it out-of-band)
        if provider == .claude {
            result.append(WireMessage(role: "system", content: LLMService.systemPrompt))
        }

        for msg in rawMessages {
            guard let role = msg["role"] as? String else { continue }

            switch role {
            case "system":
                // OpenAI system message
                let content = msg["content"] as? String ?? ""
                result.append(WireMessage(role: "system", content: content))

            case "user":
                if let text = msg["content"] as? String {
                    result.append(WireMessage(role: "user", content: text))
                } else if let contentArray = msg["content"] as? [[String: Any]] {
                    // Claude tool_result or multi-part content
                    for block in contentArray {
                        let blockType = block["type"] as? String ?? "text"
                        if blockType == "tool_result" {
                            let toolUseID = block["tool_use_id"] as? String ?? ""
                            if let contentStr = block["content"] as? String {
                                result.append(WireMessage(
                                    role: "tool_result",
                                    content: contentStr,
                                    toolInfo: "tool_use_id: \(toolUseID)"
                                ))
                            } else if let contentParts = block["content"] as? [[String: Any]] {
                                // Multi-part (text + images)
                                var texts: [String] = []
                                var imageCount = 0
                                for part in contentParts {
                                    if let text = part["text"] as? String {
                                        texts.append(text)
                                    } else if part["type"] as? String == "image" {
                                        imageCount += 1
                                    }
                                }
                                var display = texts.joined(separator: "\n")
                                if imageCount > 0 {
                                    display += "\n[\(imageCount) image(s) omitted]"
                                }
                                result.append(WireMessage(
                                    role: "tool_result",
                                    content: display,
                                    toolInfo: "tool_use_id: \(toolUseID)"
                                ))
                            }
                        } else if blockType == "text" {
                            let text = block["text"] as? String ?? ""
                            result.append(WireMessage(role: "user", content: text))
                        } else if blockType == "image_url" {
                            result.append(WireMessage(role: "user", content: "[image]"))
                        }
                    }
                }

            case "assistant":
                if let contentArray = msg["content"] as? [[String: Any]] {
                    // Claude format - content is array of blocks
                    var textParts: [String] = []
                    var toolUses: [(name: String, id: String, input: Any)] = []
                    for block in contentArray {
                        let blockType = block["type"] as? String ?? ""
                        if blockType == "text", let text = block["text"] as? String {
                            textParts.append(text)
                        } else if blockType == "tool_use" {
                            let name = block["name"] as? String ?? ""
                            let id = block["id"] as? String ?? ""
                            let input = block["input"] ?? [String: String]()
                            toolUses.append((name: name, id: id, input: input))
                        }
                    }
                    if !textParts.isEmpty {
                        result.append(WireMessage(role: "assistant", content: textParts.joined(separator: "\n")))
                    }
                    for tu in toolUses {
                        let prettyJSON = Self.prettyPrint(tu.input)
                        result.append(WireMessage(
                            role: "tool_use",
                            content: prettyJSON,
                            toolInfo: "\(tu.name) (id: \(tu.id))"
                        ))
                    }
                } else {
                    // OpenAI format
                    let text = msg["content"] as? String ?? ""
                    if let toolCalls = msg["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                        if !text.isEmpty {
                            result.append(WireMessage(role: "assistant", content: text))
                        }
                        for tc in toolCalls {
                            let id = tc["id"] as? String ?? ""
                            let funcInfo = tc["function"] as? [String: Any] ?? [:]
                            let name = funcInfo["name"] as? String ?? ""
                            let args = funcInfo["arguments"] as? String ?? "{}"
                            let prettyArgs = Self.prettyPrintJSON(args)
                            result.append(WireMessage(
                                role: "tool_use",
                                content: prettyArgs,
                                toolInfo: "\(name) (id: \(id))"
                            ))
                        }
                    } else if !text.isEmpty {
                        result.append(WireMessage(role: "assistant", content: text))
                    }
                }

            case "tool":
                // OpenAI tool result
                let toolCallID = msg["tool_call_id"] as? String ?? ""
                let content = msg["content"] as? String ?? ""
                result.append(WireMessage(
                    role: "tool_result",
                    content: content,
                    toolInfo: "tool_call_id: \(toolCallID)"
                ))

            default:
                result.append(WireMessage(role: role, content: "\(msg)"))
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Raw Conversation")
                    .font(.headline)
                Spacer()
                Text(chatState.provider.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Messages
            let messages = wireMessages
            if messages.isEmpty {
                VStack {
                    Spacer()
                    Text("No messages yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                rawMessageCard(message)
                                    .id(index)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("raw-bottom")
                        }
                        .padding(8)
                    }
                    .onChange(of: chatState.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("raw-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: chatState.messages.last?.text) { _, _ in
                        proxy.scrollTo("raw-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Message Card

    private func rawMessageCard(_ message: WireMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                roleBadge(message.role)
                if let info = message.toolInfo {
                    Text(info)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Text(message.content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 300)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func roleBadge(_ role: String) -> some View {
        Text(role)
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(roleColour(role).opacity(0.15))
            .foregroundStyle(roleColour(role))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func roleColour(_ role: String) -> Color {
        switch role {
        case "system": return .purple
        case "user": return .blue
        case "assistant": return .gray
        case "tool_use": return .orange
        case "tool_result", "tool": return .green
        default: return .secondary
        }
    }

    // MARK: - JSON Formatting

    private static func prettyPrint(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "\(obj)"
        }
        return str
    }

    private static func prettyPrintJSON(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return jsonString
        }
        return str
    }
}

// MARK: - Wire Message Model

private struct WireMessage {
    let role: String
    let content: String
    var toolInfo: String? = nil
}
