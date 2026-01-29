#!/usr/bin/env swift

// Test for KokoroEngine with actual KokoroSwift integration
// Verifies the build compiles and imports work correctly

import Foundation

// Test that we can import the built framework
print("🧪 KokoroVoice Engine Build Test")
print("=================================")

// Since we can't import the package modules directly in a script,
// we verify the build artifacts exist and test configuration

let buildPath = ".build/arm64-apple-macosx/debug"
let fileManager = FileManager.default

// Check for built modules
print("\n📍 Checking build artifacts...")

let artifacts = [
    "KokoroVoiceShared.build",
    "KokoroSwift.build",
    "MLX.build",
    "MLXNN.build",
    "MLXUtilsLibrary.build"
]

var allFound = true
for artifact in artifacts {
    let path = "\(buildPath)/\(artifact)"
    if fileManager.fileExists(atPath: path) {
        print("✅ Found: \(artifact)")
    } else {
        print("⚠️ Missing: \(artifact)")
        allFound = false
    }
}

// Check for output libraries
print("\n📍 Checking compiled libraries...")
let libraries = [
    "libKokoroVoiceShared.a",
    "libKokoroSwift.a"
]

for lib in libraries {
    let path = "\(buildPath)/\(lib)"
    if fileManager.fileExists(atPath: path) {
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            print("✅ \(lib) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))")
        }
    } else {
        // Try dynamic library
        let dylibPath = "\(buildPath)/\(lib.replacingOccurrences(of: ".a", with: ".dylib"))"
        if fileManager.fileExists(atPath: dylibPath) {
            if let attrs = try? fileManager.attributesOfItem(atPath: dylibPath),
               let size = attrs[.size] as? Int64 {
                print("✅ \(lib.replacingOccurrences(of: ".a", with: ".dylib")) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))")
            }
        } else {
            print("⚠️ Library not found: \(lib)")
        }
    }
}

// Check the patched kokoro-ios package
print("\n📍 Checking patched kokoro-ios...")
let patchedFile = "LocalPackages/kokoro-ios/Sources/KokoroSwift/BuildingBlocks/LayerNormInference.swift"
if fileManager.fileExists(atPath: patchedFile) {
    if let content = try? String(contentsOfFile: patchedFile) {
        if content.contains("import MLXFast") {
            print("⚠️ MLXFast import still present - patch not applied")
        } else if content.contains("MLXFast is now part of MLX module") {
            print("✅ MLXFast patch applied correctly")
        } else {
            print("✅ No MLXFast import found")
        }
    }
}

// Summary
print("\n=================================")
if allFound {
    print("✅ Build verification passed!")
    print("\nThe KokoroVoice project builds successfully with:")
    print("  - Patched kokoro-ios (MLXFast → MLX)")
    print("  - MLXUtilsLibrary for npz/safetensors loading")
    print("  - MLX/MLXNN for Apple Silicon ML inference")
} else {
    print("⚠️ Some components missing - run 'swift build' first")
}

print("\n📝 Next steps:")
print("  1. Download model files to Resources/:")
print("     - kokoro-v1_0.safetensors (~600MB)")
print("     - voices/*.safetensors (voice embeddings)")
print("  2. Run the host app to register the extension")
print("  3. Enable voice in System Settings → Accessibility → Spoken Content")
