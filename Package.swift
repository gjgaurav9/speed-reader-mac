// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SpeedReader",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SpeedReader",
            path: "Sources/SpeedReader"
        )
    ]
)
