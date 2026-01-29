// KokoroVoice/KokoroVoiceApp.swift
// KokoroVoice
//
// Main application entry point for the Kokoro Voice host app.

import SwiftUI

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
        // Find model resources
        if let resourceURL = Bundle.main.resourceURL {
            do {
                try await KokoroEngine.shared.loadModel(from: resourceURL)
                print("KokoroVoice: Model loaded successfully")
            } catch {
                print("KokoroVoice: Failed to load model: \(error)")
            }
        }
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
