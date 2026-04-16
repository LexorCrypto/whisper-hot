// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhisperHot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WhisperHot",
            path: "Sources/WhisperHot",
            resources: [.copy("../../Resources/Sounds")]
        ),
        .testTarget(
            name: "WhisperHotTests",
            path: "Tests/WhisperHotTests"
        )
    ]
)
