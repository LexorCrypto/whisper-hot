// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhisperHot",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "WhisperHotLib",
            path: "Sources/WhisperHot",
            exclude: ["WhisperHotApp.swift"]
        ),
        .executableTarget(
            name: "WhisperHot",
            dependencies: ["WhisperHotLib"],
            path: "Sources/WhisperHotApp"
        ),
        .testTarget(
            name: "WhisperHotTests",
            dependencies: ["WhisperHotLib"],
            path: "Tests/WhisperHotTests"
        )
    ]
)
