import Foundation

/// Handles LLM API communication with streaming SSE support.
/// Stateless enum - all methods are static.
enum LLMService {

    // MARK: - System Prompt

    static let systemPrompt = """
    You are an AI assistant integrated into a macOS jigsaw puzzle generator app. The app generates \
    jigsaw puzzle pieces from images, creates ML training datasets from piece pairs, and trains \
    Siamese Neural Networks (SNNs) to determine whether two puzzle pieces fit together.

    Key concepts:
    - **Datasets** contain pairs of puzzle piece images labelled as correct (matching) or wrong \
    (three sub-categories: wrong shape match, wrong image match, wrong nothing).
    - **Architecture presets** define SNN configurations: convolutional blocks, embedding dimension, \
    comparison method (L1/L2/concatenation), dropout, learning rate, batch size, epochs, etc.
    - **Models** are trained SNNs. Each references a dataset and an architecture.

    Important metrics:
    - **Test accuracy**: overall binary classification accuracy on the test split.
    - **R@1 (Recall@1)**: per-edge ranking - for each edge query, is the correct match ranked first? \
    This is the most practically relevant metric for a puzzle solver.
    - **Standardised results**: metrics at fixed precision targets (e.g. R@P60 = recall when precision >= 60%). \
    Allows fair cross-model comparison.
    - **F1 score**: harmonic mean of precision and recall.
    - **Confusion matrix**: TP/FP/FN/TN breakdown.
    - **Multi-class metrics**: when useFourClass is enabled, the model classifies into 5 categories \
    (correct, wrongShapeMatch, wrongOrientation, wrongImageMatch, wrongNothing) instead of binary match/non-match.

    Architecture parameters:
    - **Conv blocks**: each has filters, kernel size, batch norm, max pool. More blocks = more capacity.
    - **Embedding dimension**: size of the learned representation vector.
    - **Comparison method**: how two embeddings are compared (L1 distance, L2 distance, or concatenation).
    - **Seam-only mode**: crops thin strips from touching edges instead of using full piece images.
    - **Native resolution**: skips the CrispAlpha resize step.
    - **Mixed precision (AMP)**: uses FP16 on CUDA for faster training.

    Use the available tools proactively to look up data before answering questions. \
    Always use tools rather than guessing about the user's models, datasets, or metrics. \
    Use British English in your responses (colour, favourite, analyse, etc.).
    """

    // MARK: - Public API

    /// Streams a complete chat turn, handling tool calls automatically.
    /// Returns when the assistant has finished its final text response (no more tool calls).
    static func streamChat(
        chatState: ChatState,
        modelState: ModelState,
        datasetState: DatasetState
    ) async {
        await chatState.setStreaming(true)
        defer { Task { @MainActor in chatState.isStreaming = false } }

        // Tool call loop - keeps going until the LLM responds with pure text (no tool calls)
        var maxIterations = 10
        while maxIterations > 0 {
            maxIterations -= 1

            let messageID = await chatState.addAssistantMessage(streaming: true)

            do {
                let provider = await chatState.provider
                let toolCalls: [ChatToolCall]
                switch provider {
                case .claude:
                    toolCalls = try await streamClaude(chatState: chatState, messageID: messageID)
                case .openAI:
                    toolCalls = try await streamOpenAI(chatState: chatState, messageID: messageID)
                }

                await chatState.finaliseMessage(id: messageID, toolCalls: toolCalls)

                if toolCalls.isEmpty {
                    // No tool calls - the LLM is done
                    return
                }

                // Execute tool calls and append results
                for toolCall in toolCalls {
                    let result = await ChatToolExecutor.execute(
                        toolName: toolCall.name,
                        arguments: toolCall.arguments,
                        modelState: modelState,
                        datasetState: datasetState
                    )

                    let toolResult = ChatToolResult(
                        id: UUID().uuidString,
                        toolCallID: toolCall.id,
                        toolName: toolCall.name,
                        content: result
                    )
                    await chatState.addToolResult(toolResult)
                }

                // Loop back to send tool results to the LLM
            } catch is CancellationError {
                await chatState.finaliseMessage(id: messageID)
                return
            } catch {
                await chatState.finaliseMessage(id: messageID)
                await MainActor.run { chatState.error = error.localizedDescription }
                return
            }
        }
    }

    // MARK: - Claude API

    private static func streamClaude(chatState: ChatState, messageID: UUID) async throws -> [ChatToolCall] {
        let apiKey = ChatCredentialStore.claudeAPIKey
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        let modelID = await chatState.selectedModelID
        let messages = await buildClaudeMessages(chatState: chatState)

        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": 4096,
            "system": Self.systemPrompt,
            "messages": messages,
            "stream": true,
        ]

        let tools = ChatTools.claudeTools()
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        var toolCalls: [ChatToolCall] = []
        var currentToolID: String?
        var currentToolName: String?
        var currentToolArgs = ""

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = event["type"] as? String else { continue }

            switch eventType {
            case "content_block_start":
                if let contentBlock = event["content_block"] as? [String: Any],
                   let blockType = contentBlock["type"] as? String {
                    if blockType == "tool_use" {
                        currentToolID = contentBlock["id"] as? String
                        currentToolName = contentBlock["name"] as? String
                        currentToolArgs = ""
                    }
                }

            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   let deltaType = delta["type"] as? String {
                    if deltaType == "text_delta", let text = delta["text"] as? String {
                        await chatState.appendToMessage(id: messageID, text: text)
                    } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                        currentToolArgs += partial
                    }
                }

            case "content_block_stop":
                if let toolID = currentToolID, let toolName = currentToolName {
                    toolCalls.append(ChatToolCall(
                        id: toolID,
                        name: toolName,
                        arguments: currentToolArgs
                    ))
                    currentToolID = nil
                    currentToolName = nil
                    currentToolArgs = ""
                }

            case "message_stop":
                break

            case "error":
                if let errorInfo = event["error"] as? [String: Any],
                   let message = errorInfo["message"] as? String {
                    throw LLMError.apiError(statusCode: 0, body: message)
                }

            default:
                break
            }
        }

        return toolCalls
    }

    @MainActor
    private static func buildClaudeMessages(chatState: ChatState) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        for msg in chatState.messages {
            switch msg.role {
            case .user:
                messages.append([
                    "role": "user",
                    "content": msg.text,
                ])

            case .assistant:
                var content: [[String: Any]] = []
                if !msg.text.isEmpty {
                    content.append(["type": "text", "text": msg.text])
                }
                for tc in msg.toolCalls {
                    var toolUse: [String: Any] = [
                        "type": "tool_use",
                        "id": tc.id,
                        "name": tc.name,
                    ]
                    if let argsData = tc.arguments.data(using: .utf8),
                       let argsObj = try? JSONSerialization.jsonObject(with: argsData) {
                        toolUse["input"] = argsObj
                    } else {
                        toolUse["input"] = [String: String]()
                    }
                    content.append(toolUse)
                }
                if !content.isEmpty {
                    messages.append(["role": "assistant", "content": content])
                }

            case .toolResult:
                for result in msg.toolResults {
                    messages.append([
                        "role": "user",
                        "content": [
                            [
                                "type": "tool_result",
                                "tool_use_id": result.toolCallID,
                                "content": result.content,
                            ] as [String: Any]
                        ],
                    ])
                }

            case .toolUse:
                break
            }
        }

        return messages
    }

    // MARK: - OpenAI API

    private static func streamOpenAI(chatState: ChatState, messageID: UUID) async throws -> [ChatToolCall] {
        let apiKey = ChatCredentialStore.openAIAPIKey
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        let modelID = await chatState.selectedModelID
        let messages = await buildOpenAIMessages(chatState: chatState)

        var body: [String: Any] = [
            "model": modelID,
            "messages": messages,
            "stream": true,
        ]

        let tools = ChatTools.openAITools()
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        // OpenAI streams tool calls as incremental deltas with indices
        var toolCallBuffers: [Int: (id: String, name: String, args: String)] = [:]

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr == "[DONE]" { break }

            guard let data = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = event["choices"] as? [[String: Any]],
                  let choice = choices.first,
                  let delta = choice["delta"] as? [String: Any] else { continue }

            // Text content
            if let content = delta["content"] as? String {
                await chatState.appendToMessage(id: messageID, text: content)
            }

            // Tool calls
            if let toolCallDeltas = delta["tool_calls"] as? [[String: Any]] {
                for tc in toolCallDeltas {
                    guard let index = tc["index"] as? Int else { continue }

                    if let id = tc["id"] as? String {
                        // New tool call
                        let funcInfo = tc["function"] as? [String: Any]
                        toolCallBuffers[index] = (
                            id: id,
                            name: funcInfo?["name"] as? String ?? "",
                            args: funcInfo?["arguments"] as? String ?? ""
                        )
                    } else if let funcInfo = tc["function"] as? [String: Any] {
                        // Continuation delta
                        if let argDelta = funcInfo["arguments"] as? String {
                            toolCallBuffers[index]?.args += argDelta
                        }
                    }
                }
            }
        }

        // Convert buffered tool calls to our format
        let toolCalls = toolCallBuffers.sorted(by: { $0.key < $1.key }).map { (_, buffer) in
            ChatToolCall(id: buffer.id, name: buffer.name, arguments: buffer.args)
        }

        return toolCalls
    }

    @MainActor
    private static func buildOpenAIMessages(chatState: ChatState) -> [[String: Any]] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt],
        ]

        for msg in chatState.messages {
            switch msg.role {
            case .user:
                messages.append(["role": "user", "content": msg.text])

            case .assistant:
                var entry: [String: Any] = ["role": "assistant"]
                if !msg.text.isEmpty {
                    entry["content"] = msg.text
                }
                if !msg.toolCalls.isEmpty {
                    entry["tool_calls"] = msg.toolCalls.map { tc -> [String: Any] in
                        [
                            "id": tc.id,
                            "type": "function",
                            "function": [
                                "name": tc.name,
                                "arguments": tc.arguments,
                            ] as [String: Any],
                        ]
                    }
                }
                messages.append(entry)

            case .toolResult:
                for result in msg.toolResults {
                    messages.append([
                        "role": "tool",
                        "tool_call_id": result.toolCallID,
                        "content": result.content,
                    ])
                }

            case .toolUse:
                break
            }
        }

        return messages
    }

    // MARK: - Errors

    enum LLMError: LocalizedError {
        case missingAPIKey
        case apiError(statusCode: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No API key configured. Open settings (gear icon) to add one."
            case .apiError(let code, let body):
                if code == 0 { return body }
                return "API error (\(code)): \(body.prefix(200))"
            }
        }
    }
}

// MARK: - ChatState streaming helpers

extension ChatState {
    func setStreaming(_ value: Bool) {
        isStreaming = value
    }
}
