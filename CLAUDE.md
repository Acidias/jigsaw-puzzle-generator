# Jigsaw Puzzle Generator

Native macOS app (Swift + SwiftUI) that generates jigsaw puzzle pieces from images.

## Build & Run
- `swift build` to compile
- `swift run` to launch the app
- Requires macOS 14+
- Requires `piecemaker` Python library: `pip3 install piecemaker`
- Requires system dependencies: `brew install potrace optipng libspatialindex`

## Project Structure
- `Sources/App/` - App entry point and global state (AppState)
- `Sources/Models/` - Data models (PuzzlePiece, PuzzleConfiguration, PuzzleProject)
- `Sources/Views/` - SwiftUI views (sidebar tree, image detail, piece detail, config panel, puzzle overlay)
- `Sources/Services/`
  - `PuzzleGenerator` - Calls piecemaker via Python subprocess, parses JSON output
  - `ExportService` - Exports pieces as PNGs with metadata JSON
- `Scripts/generate_puzzle.py` - Python wrapper that calls piecemaker CLI and returns JSON metadata

## Key Concepts
- Uses piecemaker library for proper jigsaw shapes (bezier curves, tabs/blanks)
- Swift app calls Python script as subprocess, reads JSON metadata from stdout
- Piece images loaded lazily from disk (imagePath on PuzzlePiece) to keep memory low for large puzzles
- Grid size: configurable from 3x3 to 100x100 (rows x cols passed as total piece count)
- Pieces identified by numeric IDs with bounding boxes and neighbour lists
- PuzzleGenerator returns Result<GenerationResult, GenerationError> with specific error cases
- Temp output directories cleaned up on re-generation and project removal
- Export copies PNG files from disk instead of re-encoding (falls back to NSImage for lines overlay)
