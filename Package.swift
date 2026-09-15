// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "your-turn",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "your-turn",
            path: "Sources/YourTurn"
        )
    ]
)
