// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Moth",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Moth", path: "Sources/Moth")
    ]
)
