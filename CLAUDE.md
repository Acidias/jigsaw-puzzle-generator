# Jigsaw Puzzle Generator

Native macOS app (Swift + SwiftUI) that generates jigsaw puzzle pieces from images.

## Build & Run
- `swift build` to compile
- `swift run` to launch the app
- Requires macOS 14+

## Project Structure
- `Sources/App/` - App entry point and global state
- `Sources/Models/` - Data models (PuzzlePiece, PuzzleConfiguration, EdgeType, PuzzleProject)
- `Sources/Views/` - SwiftUI views (sidebar tree, image detail, piece detail, config panel, puzzle overlay)
- `Sources/Services/` - Core logic:
  - `BezierEdgeGenerator` - Generates jigsaw tab/blank shapes using cubic bezier curves
  - `ImageClipper` - Clips image regions to bezier paths using Core Graphics
  - `PuzzleGenerator` - Orchestrates the full generation pipeline
  - `ExportService` - Exports pieces as PNGs with metadata JSON

## Key Concepts
- Edge grid: horizontal and vertical edges assigned tab/blank/flat types with a seeded RNG
- Tab shapes: cubic bezier curves with neck pinch and rounded head for interlocking
- Coordinate handling: paths use top-down coords, converted to CG bottom-up for clipping
- Grid size: configurable from 3x3 to 100x100
