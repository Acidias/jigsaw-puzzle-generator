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
        ChatToolDefinition(
            name: "get_sample_pairs",
            description: "Get sample piece pair images from a dataset with full metadata. Returns the actual images (left and right pieces) alongside pair_id, category, label, puzzle_id, left_piece_id, right_piece_id, direction, left_edge_index, and file paths.",
            parameters: [
                ChatToolParam(name: "dataset_id", description: "The UUID of the dataset to sample from"),
                ChatToolParam(name: "split", description: "Which split to sample from: train, test, or valid (default: test)", isRequired: false),
                ChatToolParam(name: "category", description: "Optional category filter: correct, wrongShapeMatch, wrongOrientation, wrongImageMatch, or wrongNothing", isRequired: false),
                ChatToolParam(name: "count", type: "integer", description: "Number of pairs to return (default: 3, max: 5)", isRequired: false),
            ]
        ),
        ChatToolDefinition(
            name: "list_projects",
            description: "List all puzzle projects with their images and cuts. Returns project id, name, image count, cut summaries (id, grid size, piece count per image), and created date.",
            parameters: []
        ),
        ChatToolDefinition(
            name: "get_piece_images",
            description: "Get piece images from a project cut with full metadata. Returns the actual piece images alongside piece numeric ID, grid row/col (grid indices), piece type (corner/edge/interior), bounding box, and neighbour IDs.",
            parameters: [
                ChatToolParam(name: "project_id", description: "The UUID of the project"),
                ChatToolParam(name: "cut_id", description: "The UUID of the cut within the project"),
                ChatToolParam(name: "image_name", description: "Optional filter by source image name (returns pieces from the first matching image result)", isRequired: false),
                ChatToolParam(name: "count", type: "integer", description: "Number of pieces to return (default: 4, max: 8)", isRequired: false),
            ]
        ),

        // MARK: - Write Tools

        ChatToolDefinition(
            name: "create_model",
            description: "Create a new Siamese model from an architecture preset and dataset. Generates the initial train.py script. The model appears in the sidebar immediately.",
            parameters: [
                ChatToolParam(name: "preset_id", description: "The UUID of the architecture preset to use"),
                ChatToolParam(name: "dataset_id", description: "The UUID of the dataset to train on"),
                ChatToolParam(name: "name", description: "Name for the new model"),
                ChatToolParam(name: "notes", description: "Optional notes/description for the model", isRequired: false),
            ]
        ),
        ChatToolDefinition(
            name: "read_training_script",
            description: "Read the current train.py script for a model. If no script exists yet, generates one from the model's architecture. Returns the full Python source code.",
            parameters: [
                ChatToolParam(name: "model_id", description: "The UUID of the model whose training script to read"),
            ]
        ),
        ChatToolDefinition(
            name: "update_training_script",
            description: "Replace the train.py script for a model with new content. Use this to modify hyperparameters, change the training loop, add data augmentation, etc. IMPORTANT: preserve the metrics.json output format so the app can import results.",
            parameters: [
                ChatToolParam(name: "model_id", description: "The UUID of the model whose training script to update"),
                ChatToolParam(name: "script", description: "The full Python source code for the new train.py"),
            ]
        ),
        ChatToolDefinition(
            name: "start_training",
            description: "Start local training for a model. Training runs asynchronously - this returns immediately. Requires python3 to be available. If a custom train.py exists, it will be used as-is (not regenerated).",
            parameters: [
                ChatToolParam(name: "model_id", description: "The UUID of the model to train"),
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
