// KokoroVoice/KokoroVoiceApp.swift
// KokoroVoice
//
// Main application entry point for the Kokoro Voice host app.

import SwiftUI
import KokoroVoiceShared

@main
struct KokoroVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 700)
        .commands {
            // Custom menu commands
            CommandGroup(replacing: .help) {
                Button("Kokoro Voice Help") {
                    if let url = URL(string: "https://github.com/mlalma/kokoro-ios") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button("Open Accessibility Settings...") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView(voiceManager: VoiceManager())
        }
        #endif
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("KokoroVoice: Application launched")

        // Load model in background
        Task {
            await loadModel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("KokoroVoice: Application terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running in background to maintain voice registration
        return false
    }

    private func loadModel() async {
        // Try multiple locations for model files
        let possiblePaths = [
            // 1. App bundle resources (production)
            Bundle.main.resourceURL,
            // 2. Development: project Resources directory
            Bundle.main.bundleURL
                .deletingLastPathComponent() // Contents
                .deletingLastPathComponent() // KokoroVoice.app
                .deletingLastPathComponent() // Debug
                .deletingLastPathComponent() // Products
                .deletingLastPathComponent() // Build
                .deletingLastPathComponent() // DerivedData/...
                .appendingPathComponent("SourcePackages")
                .deletingLastPathComponent()
                .appendingPathComponent("Resources"),
            // 3. Fallback: hardcoded development path
            URL(fileURLWithPath: "/Users/tag/Documents/workspace-playground/kokoro-voice/KokoroVoice/Resources")
        ].compactMap { $0 }

        for resourceURL in possiblePaths {
            let modelFile = resourceURL.appendingPathComponent("kokoro-v1_0.safetensors")
            if FileManager.default.fileExists(atPath: modelFile.path) {
                do {
                    try await KokoroEngine.shared.loadModel(from: resourceURL)
                    print("KokoroVoice: Model loaded successfully from \(resourceURL.path)")
                    return
                } catch {
                    print("KokoroVoice: Failed to load model from \(resourceURL.path): \(error)")
                }
            }
        }

        print("KokoroVoice: Model not found. Please download model files to Resources/")
        print("KokoroVoice: Expected: kokoro-v1_0.safetensors and voices/*.safetensors")
    }
}

// MARK: - App Icon Badge (for status indication)

extension NSApplication {
    func updateDockBadge(enabledVoiceCount: Int) {
        if enabledVoiceCount > 0 {
            dockTile.badgeLabel = "\(enabledVoiceCount)"
        } else {
            dockTile.badgeLabel = nil
        }
    }
}
