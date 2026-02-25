// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JigsawPuzzleGenerator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "JigsawPuzzleGenerator",
            path: "Sources",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
