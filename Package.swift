// swift-tools-version: 6.0
// Package.swift - For testing shared components without Xcode project

import PackageDescription

let package = Package(
    name: "KokoroVoice",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "KokoroVoiceShared",
            targets: ["KokoroVoiceShared"]
        ),
        .library(
            name: "KokoroVoiceExtension",
            targets: ["KokoroVoiceExtension"]
        ),
    ],
    dependencies: [
        // Note: kokoro-ios currently has compatibility issue with mlx-swift 0.30+ (MLXFast import)
        // Commented out until upstream fix. Using stub implementation for testing.
        // .package(url: "https://github.com/mlalma/kokoro-ios.git", from: "1.0.8"),
        // .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", branch: "main"),
    ],
    targets: [
        // Shared library with constants, voice configuration, and engine wrapper
        .target(
            name: "KokoroVoiceShared",
            dependencies: [
                // Dependencies commented out until kokoro-ios fixes MLXFast compatibility
            ],
            path: "Shared"
        ),

        // Extension with SSML parser and Audio Unit
        .target(
            name: "KokoroVoiceExtension",
            dependencies: [
                "KokoroVoiceShared",
            ],
            path: "KokoroVoiceExtension",
            exclude: [
                "Info.plist",
                "KokoroVoiceExtension.entitlements"
            ]
        ),

        // Unit tests
        .testTarget(
            name: "SSMLParserTests",
            dependencies: ["KokoroVoiceExtension"],
            path: "Tests/SSMLParserTests"
        ),

        .testTarget(
            name: "VoiceConfigurationTests",
            dependencies: ["KokoroVoiceShared"],
            path: "Tests/VoiceConfigurationTests"
        ),
    ]
)
