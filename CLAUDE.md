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
  - `ImageAttribution` - Openverse licence/creator info
  - `ProjectManifest` - Codable DTOs for JSON persistence (ProjectManifest, ImageManifest, CutManifest, CutImageResultManifest, PieceManifest)
- `Sources/Views/` - SwiftUI views (four-level sidebar tree, project/cut/cutImage/piece detail, config panel, puzzle overlay, batch processing, Openverse search)
- `Sources/Services/`
  - `PuzzleGenerator` - Orchestrates native puzzle generation, returns Result<GenerationResult, GenerationError>
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
- **Disk layout**: `projects/<project-uuid>/manifest.json` + `images/<image-uuid>/source.<ext>` + `cuts/<cut-uuid>/<image-uuid>/pieces/*.png` + `lines.png`
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
