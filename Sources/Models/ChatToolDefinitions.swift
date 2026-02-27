import Foundation

// MARK: - Tool Definition

struct ChatToolParam {
    let name: String
    let type: String  // "string", "array"
    let description: String
    let isRequired: Bool
    let itemType: String?  // for arrays

    init(name: String, type: String = "string", description: String, isRequired: Bool = true, itemType: String? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.isRequired = isRequired
        self.itemType = itemType
    }
}

struct ChatToolDefinition {
    let name: String
    let description: String
    let parameters: [ChatToolParam]

    /// Convert to Claude API `tools` array element.
    func toClaudeJSON() -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in parameters {
            var prop: [String: Any] = [
                "type": param.type,
                "description": param.description,
            ]
            if param.type == "array", let itemType = param.itemType {
                prop["items"] = ["type": itemType]
            }
            properties[param.name] = prop
            if param.isRequired {
                required.append(param.name)
            }
        }

        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty {
            schema["required"] = required
        }

        return [
            "name": name,
            "description": description,
            "input_schema": schema,
        ]
    }

    /// Convert to OpenAI API `tools` array element.
    func toOpenAIJSON() -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in parameters {
            var prop: [String: Any] = [
                "type": param.type,
                "description": param.description,
            ]
            if param.type == "array", let itemType = param.itemType {
                prop["items"] = ["type": itemType]
            }
            properties[param.name] = prop
            if param.isRequired {
                required.append(param.name)
            }
        }

        var params: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty {
            params["required"] = required
        }

        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": params,
            ] as [String: Any],
        ]
    }
}

// MARK: - Tool Registry

enum ChatTools {
    static let allTools: [ChatToolDefinition] = [
        ChatToolDefinition(
            name: "list_models",
            description: "List all Siamese neural network models with their status, test accuracy, ranking metrics, and architecture summary.",
            parameters: []
        ),
        ChatToolDefinition(
            name: "get_model_detail",
            description: "Get full details for a specific model including architecture configuration and all training metrics.",
            parameters: [
                ChatToolParam(name: "model_id", description: "The UUID of the model to retrieve"),
            ]
        ),
        ChatToolDefinition(
            name: "list_datasets",
            description: "List all generated datasets with their grid configuration, pair counts, and source project.",
            parameters: []
        ),
        ChatToolDefinition(
            name: "get_dataset_detail",
            description: "Get full configuration and split/category counts for a specific dataset.",
            parameters: [
                ChatToolParam(name: "dataset_id", description: "The UUID of the dataset to retrieve"),
            ]
        ),
        ChatToolDefinition(
            name: "list_presets",
            description: "List all architecture presets with their block count, embedding dimension, and built-in flag.",
            parameters: []
        ),
        ChatToolDefinition(
            name: "get_preset_detail",
            description: "Get the full SiameseArchitecture configuration for a specific preset.",
            parameters: [
                ChatToolParam(name: "preset_id", description: "The UUID of the preset to retrieve"),
            ]
        ),
        ChatToolDefinition(
            name: "get_training_report",
            description: "Get a comprehensive training report for a model, including architecture, dataset config, all metrics (per-epoch, test, standardised, ranking, confusion matrix), and training script excerpt.",
            parameters: [
                ChatToolParam(name: "model_id", description: "The UUID of the model to get the report for"),
            ]
        ),
        ChatToolDefinition(
            name: "compare_models",
            description: "Compare multiple models side by side with key metrics: test accuracy, F1, R@P60, R@P70, R@1, training duration, and architecture summary.",
            parameters: [
                ChatToolParam(
                    name: "model_ids",
                    type: "array",
                    description: "Array of model UUIDs to compare",
                    itemType: "string"
                ),
            ]
        ),
    ]

    static func claudeTools() -> [[String: Any]] {
        allTools.map { $0.toClaudeJSON() }
    }

    static func openAITools() -> [[String: Any]] {
        allTools.map { $0.toOpenAIJSON() }
    }
}
