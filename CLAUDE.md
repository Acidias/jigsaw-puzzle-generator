# Jigsaw Puzzle Generator

Native macOS app (Swift + SwiftUI) that generates jigsaw puzzle pieces from images.

## Build & Run
- `./build.sh` to compile and launch as a proper .app bundle (required for keyboard input in TextFields)
- `swift build` to compile only
- Requires macOS 14+
- No external dependencies - pure native Swift with Core Graphics
- App sets `NSApplication.shared.setActivationPolicy(.regular)` at launch so SPM-built executables get full keyboard focus

## Project Structure
- `Sources/App/` - App entry point and global state (AppState with four-level selection: project > cut > cutImage > piece)
- `Sources/Models/` - Data models:
  - `PuzzleProject` - Named container grouping multiple images and project-level cuts
  - `PuzzleImage` - Single source image with attribution (pure container, no cuts)
  - `PuzzleCut` - Project-level puzzle generation (grid config applied to all images, contains CutImageResults)
  - `CutImageResult` - Per-image result within a cut (pieces, lines overlay, progress)
  - `PuzzlePiece` - Individual puzzle piece with bounding box and image path
  - `PuzzleConfiguration` - Grid size config (rows/columns)
  - `BatchState` - Batch processing queue and logic
  - `DatasetState` - ML dataset generation state (config, status, categories, splits, persisted datasets list)
  - `PuzzleDataset` - Persisted dataset entity (independent top-level, references source project by ID)
  - `DatasetManifest` - Codable DTO for dataset JSON persistence
  - `SiameseArchitecture` - SNN architecture config (ConvBlock, ComparisonMethod, DevicePreference, hyperparameters, useNativeResolution, useMixedPrecision, useFourClass, useSeamOnly, seamWidth)
  - `ArchitecturePreset` - Persisted architecture preset entity (name, architecture, isBuiltIn flag, independent top-level). Three built-in defaults: Quick Test, Recommended, High Capacity
  - `ArchitecturePresetManifest` - Codable DTO for preset JSON persistence
  - `TrainingMetrics` - Imported training metrics for charting (per-epoch loss/accuracy, test results, standardised results with Int precision targets, ranking metrics R@1/5/10 with per-edge info, training run info, optional FourClassMetrics)
  - `SiameseModel` - Persisted SNN model entity (architecture, status, metrics, experiment metadata: sourcePresetName, notes, trainedAt, scriptHash)
  - `ModelManifest` - Codable DTO for model JSON persistence (custom decoder for backwards compat with old manifests)
  - `ModelState` - Central state for model and preset management (models list, presets list, CRUD, training status/log/live metrics, training target, cloud config)
  - `TrainingTarget` - Enum for local vs cloud (SSH) training target
  - `CloudConfig` - SSH connection config (hostname, username, key path, port, remote work dir) + `CloudConfigStore` for persistence
  - `ChatState` - AI chat assistant state (messages, provider/model selection, streaming status, OAuth state, credential store via UserDefaults)
  - `ChatToolDefinitions` - Tool schemas for LLM function calling (19 tools: 11 read-only + 4 data preparation + 4 write tools, generates both Claude and OpenAI wire formats)
  - `ImageAttribution` - Openverse licence/creator info
  - `ProjectManifest` - Codable DTOs for JSON persistence (ProjectManifest, ImageManifest, CutManifest, CutImageResultManifest, PieceManifest)
- `Sources/Views/` - SwiftUI views (four-level sidebar tree, project/cut/cutImage/piece detail, config panel, puzzle overlay, batch processing, Openverse search, dataset generation, architecture presets panel/detail, model training/detail with Charts, ArchitectureEditorView reusable component, AI chat panel with settings popover and message bubbles, raw conversation debug panel)
- `Sources/Services/`
  - `PuzzleGenerator` - Orchestrates native puzzle generation, returns Result<GenerationResult, GenerationError>. Accepts optional `gridEdges:` to reuse shared edges across images.
  - `DatasetGenerator` - Generates structured ML training datasets from 2-piece puzzles (5 categories, train/test/valid splits), persists to internal storage
  - `DatasetStore` - Persistence layer for datasets: save/load/delete/export to ~/Library/Application Support/JigsawPuzzleGenerator/datasets/
  - `ModelStore` - Persistence layer for SNN models: save/load/delete + metrics/Core ML import to ~/Library/Application Support/JigsawPuzzleGenerator/models/
  - `ArchitecturePresetStore` - Persistence layer for architecture presets: save/load/delete to ~/Library/Application Support/JigsawPuzzleGenerator/presets/
  - `TrainingScriptGenerator` - Generates self-contained PyTorch training scripts + requirements.txt from SiameseArchitecture config. Has `writeTrainingFiles()` for in-app training (no dataset copy). Both write methods return SHA-256 hex hash of the generated script for experiment tracking.
  - `TrainingRunner` - Subprocess manager for local automated training: finds python3, creates venv, runs pip install + train.py, streams stdout for live epoch progress, auto-imports metrics.json and model.mlpackage on completion. Training working directory: `models/<model-uuid>/training/`. Supports `skipScriptGeneration` flag to preserve custom train.py scripts.
  - `CloudTrainingRunner` - SSH-based cloud training: uploads dataset + scripts via scp, runs pip install + train.py over ssh, streams stdout for live epoch progress (reuses TrainingRunner.parseEpochLine), downloads and imports results on completion
  - `LLMService` - Multi-provider LLM API integration (Claude + OpenAI) with SSE streaming, system prompt, tool call loop. `buildClaudeMessages()`/`buildOpenAIMessages()` are internal for raw conversation panel. Claude auth: OAuth Bearer token (priority) or x-api-key header
  - `ClaudeOAuthService` - OAuth 2.0 + PKCE flow for Claude account authentication (WKWebView login, token exchange/refresh, UserDefaults storage)
  - `ChatToolExecutor` - Maps LLM tool calls to app data (ModelState, DatasetState, AppState, ModelStore.buildTrainingReport). 19 tools: 11 read-only (list/get models, datasets, presets, training reports, model comparison, 3 image-returning tools), 4 data preparation (create_project, search_openverse, download_images, generate_dataset), plus 4 write tools (create_model, read_training_script, update_training_script, start_training). Openverse search results cached for attribution on download. Async execute() method. Returns (String, [ToolResultImage]) tuple for image support.
  - `ExportService` - Exports pieces as PNGs with metadata JSON (includes attribution when sourced from Openverse)
  - `OpenverseAPI` - Openverse image search API client (search, download, attribution)
  - `ProjectStore` - Persistence layer: saves/loads projects to ~/Library/Application Support/JigsawPuzzleGenerator/
  - `PuzzleEngine/` - Native jigsaw piece generation engine:
    - `EdgePath` - Bezier curve generation for jigsaw edges (4 cubic curves per edge)
    - `PiecePathBuilder` - Builds closed CGPath outlines per piece from shared grid edges
    - `PieceClipper` - Clips source image with piece paths, saves transparent PNGs
    - `LinesRenderer` - Renders cut lines overlay image for the puzzle view
    - `ImageScaler` - Upscales small images for smooth bezier edges

## Key Concepts
- **Project hierarchy**: Projects group multiple images. Cuts are project-level and apply to all images at once. Four-level sidebar: Project > Cut (e.g. "5x5") > CutImageResult (per image) > Pieces. Source images visible only in the project detail view.
- **Persistence**: Projects saved as manifest.json + files in ~/Library/Application Support/JigsawPuzzleGenerator/projects/<uuid>/. Source images copied permanently, piece PNGs moved from temp to permanent storage after generation. Survives app restart.
- **Disk layout**: `projects/<project-uuid>/manifest.json` + `images/<image-uuid>/source.<ext>` + `cuts/<cut-uuid>/<image-uuid>/pieces/*.png` + `lines.png`. Datasets: `datasets/<dataset-uuid>/manifest.json` + `{train,test,valid}/<category>/pair_NNNN_{left,right}.png` + `labels.csv`. Presets: `presets/<preset-uuid>/manifest.json`. Models: `models/<model-uuid>/manifest.json` + `metrics.json` + `model.mlpackage/` + `training/` (train.py, requirements.txt, best_model.pth). Chat: `chat/session.json`
- Jigsaw shapes generated natively using CGPath cubic bezier curves (port of piecemaker's interlocking nubs algorithm)
- Each edge has 4 bezier segments with randomised control points for natural-looking tabs/blanks
- Adjacent pieces share edge curves (one traverses forward, the other reversed) for perfect interlocking
- Piece images clipped via CGContext and saved as transparent PNGs to disk for lazy loading
- **AI normalisation**: optional pipeline that centre-crops source to grid aspect ratio, resizes to exact `cols*pieceSize x rows*pieceSize`, generates pieces, then pads all pieces to uniform square canvas with configurable fill (none/black/white/average grey). Ensures identical pixel dimensions across all pieces for ML training.
- Grid size: configurable from 1x2 to 100x100
- Pieces identified by numeric IDs with bounding boxes and neighbour lists
- Adjacency computed from grid position (trivial on a regular grid)
- Export copies PNG files from disk instead of re-encoding (falls back to NSImage for lines overlay)
- Batch processing: select multiple local images, creates a single project-level cut with CutImageResult per batch item, per-item and overall progress, skip/fail handling, optional auto-export
- Openverse integration: search Creative Commons images, filter by size/category/licence type/max results (20-500), download selected images directly into a project (existing or new) with licence/attribution preserved through to export metadata JSON
- **Architecture presets**: Reusable architecture configurations persisted as first-class entities. Three built-in defaults (Quick Test, Recommended, High Capacity) seeded on first launch via deterministic UUIDs. Presets managed in ModelState alongside models. Sidebar: AI Tools > Architecture Presets + individual preset entries. ArchitectureEditorView reused for editing.
- **Model training workflow**: Pick an architecture preset + dataset in Model Training panel -> Either export training package for external training, run automated local training via TrainingRunner (requires python3), or run cloud training via CloudTrainingRunner (requires SSH access to GPU instance). inputSize auto-overridden from dataset canvas size. Local training: creates venv, runs pip install + train.py as subprocess. Cloud training (SSH): uploads dataset + scripts via scp, runs pip install + train.py over ssh, downloads results on completion. Both stream live epoch progress with real-time chart updates, auto-import metrics.json + model.mlpackage on completion. Cloud training auto-sets device to CUDA. SSH config (hostname, user, key, port, remote dir) persisted to cloud_config.json. Manual flow still supported: export -> train externally -> import results. Models persisted with status lifecycle: designed -> training -> trained (training reverts to designed on crash). Device preference (Auto/MPS/CUDA/CPU) controls PyTorch device selection in generated script. Native resolution toggle skips CrispAlphaResize. Mixed precision (AMP) uses FP16 on CUDA with GradScaler. Smart NUM_WORKERS based on CPU count. Training speed (pairs/sec) logged per epoch. Multi-class output toggle switches from binary to 5-class softmax (CrossEntropyLoss, P(correct) as match score). Seam-only input toggle crops fixed-width strips from touching edges (SeamCropper class, configurable seamWidth 16-128px). Per-edge ranking groups test pairs by (puzzle_id, left_piece_id, direction) for realistic candidate pools; falls back to global ranking for old datasets.
- **Experiment version control**: Models track sourcePresetName (which preset created them), notes (free-text annotation), trainedAt (completion timestamp), and scriptHash (SHA-256 of generated train.py - detects code generator changes even with identical architecture params). Sidebar shows test accuracy for trained models. Model detail view shows experiment metadata row + notes editor + ranking metrics (R@1/5/10) + training run info (batch size, AMP, input size, pairs/sec). Model Training panel includes a comparison table listing all models with R@P60, R@P70, R@1 columns.
- **AI Chat assistant**: In-app LLM chat with tool use. Supports Claude API and OpenAI API (switchable). 19 tools: 11 read-only (list/get models, datasets, presets, training reports, model comparison, vision tools), 4 data preparation (create_project, search_openverse, download_images, generate_dataset), plus 4 write tools (create_model, read_training_script, update_training_script, start_training) giving the LLM full end-to-end control from data sourcing to training. Openverse search results cached in static var for attribution on download. Vision tools return base64-encoded images alongside rich metadata. Claude: images embedded in tool_result content blocks. OpenAI: images injected as follow-up user messages with data URI image_url parts. Image thumbnails displayed in chat UI inside tool result DisclosureGroups. SSE streaming via URLSession.bytes(for:). Claude auth: OAuth 2.0 + PKCE (WKWebView login window) for Pro/Max plan usage, or API key fallback. OAuth tokens stored in UserDefaults, auto-refreshed. API keys stored in UserDefaults. Chat session persisted to ~/Library/Application Support/JigsawPuzzleGenerator/chat/session.json (auto-saves on message changes, loaded on app launch). Sidebar: AI Tools > AI Chat. Raw conversation debug panel (toggleable via settings) shows wire-format messages in HSplitView with role badges, pretty-printed tool call JSON, persisted to UserDefaults.
- **Dataset generation**: generates ML training datasets from jigsaw puzzle piece pairs with configurable grid size (rows x columns, default 1x2). Adjacent pair positions = rows*(cols-1) + (rows-1)*cols - larger grids produce more pair positions and diverse piece types (corners, edges, interior). Five pair categories: correct (matching shape+image), wrong shape match (same edges, different image), wrong orientation (correct neighbours but swapped left/right order), wrong image match (same image, different edges), wrong nothing (different both). Image-level train/test/valid split prevents data leakage. Shared GridEdges enable shape-match pairs across images. Datasets are persisted as first-class entities in internal storage (independent of source project, survive project deletion). Can be exported to external directories. Visible in sidebar under "AI Tools" with detail view showing config and split/category counts. Labels.csv includes piece identity columns (puzzle_id, left_piece_id, right_piece_id, direction, left_edge_index) for per-edge assessment grouping.
