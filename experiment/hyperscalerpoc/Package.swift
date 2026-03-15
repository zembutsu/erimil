// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HyperscalerPoC",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HyperscalerPoC",
            path: "Sources/HyperscalerPoC"
        )
    ]
)
