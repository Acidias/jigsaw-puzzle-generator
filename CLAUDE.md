# Jigsaw Puzzle Generator

Native macOS app (Swift + SwiftUI) that generates jigsaw puzzle pieces from images.

## Build & Run
- `swift build` to compile
- `swift run` to launch the app
- Requires macOS 14+
- No external dependencies - pure native Swift with Core Graphics

## Project Structure
- `Sources/App/` - App entry point and global state (AppState)
- `Sources/Models/` - Data models (PuzzlePiece, PuzzleConfiguration, PuzzleProject, BatchState, ImageAttribution)
- `Sources/Views/` - SwiftUI views (sidebar tree, image detail, piece detail, config panel, puzzle overlay, batch processing)
- `Sources/Services/`
  - `PuzzleGenerator` - Orchestrates native puzzle generation, returns Result<GenerationResult, GenerationError>
  - `ExportService` - Exports pieces as PNGs with metadata JSON (includes attribution when sourced from Openverse)
  - `OpenverseAPI` - Openverse image search API client (search, download, attribution)
  - `PuzzleEngine/` - Native jigsaw piece generation engine:
    - `EdgePath` - Bezier curve generation for jigsaw edges (4 cubic curves per edge)
    - `PiecePathBuilder` - Builds closed CGPath outlines per piece from shared grid edges
    - `PieceClipper` - Clips source image with piece paths, saves transparent PNGs
    - `LinesRenderer` - Renders cut lines overlay image for the puzzle view
    - `ImageScaler` - Upscales small images for smooth bezier edges

## Key Concepts
- Jigsaw shapes generated natively using CGPath cubic bezier curves (port of piecemaker's interlocking nubs algorithm)
- Each edge has 4 bezier segments with randomised control points for natural-looking tabs/blanks
- Adjacent pieces share edge curves (one traverses forward, the other reversed) for perfect interlocking
- Piece images clipped via CGContext and saved as transparent PNGs to disk for lazy loading
- Grid size: configurable from 1x2 to 100x100
- Pieces identified by numeric IDs with bounding boxes and neighbour lists
- Adjacency computed from grid position (trivial on a regular grid)
- Temp output directories cleaned up on re-generation and project removal
- Export copies PNG files from disk instead of re-encoding (falls back to NSImage for lines overlay)
- Batch processing: select multiple images, process all with shared grid settings, per-item and overall progress, skip/fail handling, optional auto-export (Cmd+Shift+B or toolbar button)
- Openverse integration: search Creative Commons images from the batch window, filter by size/category, download selected images into batch queue with licence/attribution preserved through to export metadata JSON
