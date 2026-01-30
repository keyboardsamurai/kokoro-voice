// KokoroVoice/ContentView.swift
// KokoroVoice
//
// Main content view for the Kokoro Voice host application.
// Provides UI for enabling/disabling voices and testing them.

import SwiftUI
import KokoroVoiceShared

// MARK: - Content View

struct ContentView: View {
    @StateObject private var voiceManager = VoiceManager()
    @State private var testText = "Hello! Welcome to Kokoro Voice, a neural text-to-speech system."
    @State private var searchText = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Voice list
                voiceList

                Divider()

                // Test panel
                testPanel
            }
            .navigationTitle("Kokoro Voices")
            .toolbar {
                toolbarContent
            }
            .searchable(text: $searchText, prompt: "Search voices")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(voiceManager: voiceManager)
        }
    }

    // MARK: - Voice List

    private var voiceList: some View {
        List {
            // American English Section
            Section("American English") {
                ForEach(filteredVoices(for: "en-US")) { voice in
                    VoiceRow(voice: voice, voiceManager: voiceManager)
                }
            }

            // British English Section
            Section("British English") {
                ForEach(filteredVoices(for: "en-GB")) { voice in
                    VoiceRow(voice: voice, voiceManager: voiceManager)
                }
            }

            // Info Section
            Section {
                statusView
            }
        }
        .listStyle(.inset)
    }

    private func filteredVoices(for language: String) -> [VoiceConfiguration] {
        let languageVoices = voiceManager.voices.filter { $0.language == language }

        if searchText.isEmpty {
            return languageVoices
        }

        return languageVoices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Test Panel

    private var testPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Voice")
                .font(.headline)

            HStack {
                TextField("Enter text to speak", text: $testText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Button {
                    if voiceManager.isSpeaking {
                        voiceManager.stopSpeaking()
                    } else if let selectedVoice = voiceManager.enabledVoices.first {
                        voiceManager.testVoice(selectedVoice, text: testText)
                    }
                } label: {
                    Image(systemName: voiceManager.isSpeaking ? "stop.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(voiceManager.enabledVoices.isEmpty)
            }

            if voiceManager.enabledVoices.isEmpty {
                Text("Enable at least one voice to test.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Status View

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Enabled Voices:")
                Spacer()
                Text("\(voiceManager.enabledVoices.count) of \(voiceManager.voices.count)")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Model Status:")
                Spacer()
                Text(voiceManager.modelStatus.description)
                    .foregroundColor(voiceManager.modelStatus.isReady ? .green : .secondary)
            }

            Text("Enable voices above to make them available in System Settings → Accessibility → Spoken Content.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Enable All") {
                    voiceManager.enableAllVoices()
                }

                Button("Disable All") {
                    voiceManager.disableAllVoices()
                }

                Divider()

                Button {
                    voiceManager.refreshVoices()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
            }
        }
    }
}

// MARK: - Voice Row

struct VoiceRow: View {
    let voice: VoiceConfiguration
    @ObservedObject var voiceManager: VoiceManager
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            // Voice info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(voice.name)
                        .font(.headline)

                    if voice.quality == .a {
                        Text("HQ")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 8) {
                    Label(voice.gender.rawValue, systemImage: voice.gender == .female ? "person.fill" : "person.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(voice.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                }
            }

            Spacer()

            // Play button
            Button {
                if voiceManager.selectedVoiceId == voice.id && voiceManager.isSpeaking {
                    voiceManager.stopSpeaking()
                } else {
                    voiceManager.testVoice(voice)
                }
            } label: {
                Image(systemName: voiceManager.selectedVoiceId == voice.id && voiceManager.isSpeaking ? "stop.circle.fill" : "play.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .help("Test this voice")

            // Enable toggle
            Toggle("", isOn: Binding(
                get: { voice.isEnabled },
                set: { _ in voiceManager.toggleVoice(voice) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help(voice.isEnabled ? "Disable this voice" : "Enable this voice")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var voiceManager: VoiceManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Kokoro Model", value: "v1.0 (82M parameters)")
                    LabeledContent("Sample Rate", value: "24 kHz")
                }

                Section("Voice Files") {
                    LabeledContent("Total Voices", value: "\(Constants.availableVoices.count)")
                    LabeledContent("Languages", value: "English (US, GB)")

                    Link("View on HuggingFace", destination: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!)
                }

                Section("Troubleshooting") {
                    Text("If voices don't appear in System Settings, try:")
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Enable at least one voice above")
                        Text("2. Wait 30 seconds for registration")
                        Text("3. Restart this app")
                        Text("4. Check System Settings → Accessibility → Spoken Content")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Section {
                    Button("Open Spoken Content Settings") {
                        #if os(macOS)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Accessibility_SpeakingText") {
                            NSWorkspace.shared.open(url)
                        }
                        #endif
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
