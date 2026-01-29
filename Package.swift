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
        // Use local patched version (removed MLXFast import, now part of MLX)
        .package(path: "LocalPackages/kokoro-ios"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", branch: "main"),
    ],
    targets: [
        // Shared library with constants, voice configuration, and engine wrapper
        .target(
            name: "KokoroVoiceShared",
            dependencies: [
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
            ],
            path: "Shared"
        ),

        // Extension with SSML parser and Audio Unit
        .target(
            name: "KokoroVoiceExtension",
            dependencies: [
                "KokoroVoiceShared",
                .product(name: "KokoroSwift", package: "kokoro-ios"),
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
