//
//  AudioRecorderView.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import SwiftUI
import AVFoundation
import Combine

struct AudioRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    let memoryService: MemoryService
    let userId: UUID
    let eventId: UUID?
    let onComplete: () -> Void

    @StateObject private var audioRecorder = AudioRecorder()
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Voice Memo")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 32)

                Spacer()

                // Recording Visualizer
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: audioRecorder.isRecording ? [.red, .orange] : [.gray, .secondary]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(audioRecorder.isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: audioRecorder.isRecording)

                    Image(systemName: audioRecorder.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                }

                // Duration
                if audioRecorder.isRecording || audioRecorder.recordingURL != nil {
                    Text(formatTime(audioRecorder.recordingDuration))
                        .font(.title)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }

                Spacer()

                // Controls
                VStack(spacing: 16) {
                    if audioRecorder.recordingURL == nil {
                        // Record Button
                        Button(action: {
                            if audioRecorder.isRecording {
                                audioRecorder.stopRecording()
                            } else {
                                audioRecorder.startRecording()
                            }
                        }) {
                            HStack {
                                Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.title2)
                                Text(audioRecorder.isRecording ? "Stop Recording" : "Start Recording")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(audioRecorder.isRecording ? Color.red : Color.blue)
                            .cornerRadius(15)
                        }
                    } else {
                        // Playback & Save Controls
                        HStack(spacing: 12) {
                            // Play Button
                            Button(action: {
                                if audioRecorder.isPlaying {
                                    audioRecorder.stopPlayback()
                                } else {
                                    audioRecorder.playRecording()
                                }
                            }) {
                                HStack {
                                    Image(systemName: audioRecorder.isPlaying ? "stop.fill" : "play.fill")
                                    Text(audioRecorder.isPlaying ? "Stop" : "Play")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(15)
                            }

                            // Re-record Button
                            Button(action: {
                                audioRecorder.deleteRecording()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray)
                                    .cornerRadius(15)
                            }
                        }

                        // Save Button
                        Button(action: saveAudio) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Save Memory")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(Color.green)
                        .cornerRadius(15)
                        .disabled(isProcessing)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        audioRecorder.cleanup()
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func saveAudio() {
        guard let url = audioRecorder.recordingURL else {
            errorMessage = "No recording available"
            return
        }

        isProcessing = true
        Task {
            do {
                try await memoryService.createAudioMemory(userId: userId, audioURL: url, eventId: eventId)
                await MainActor.run {
                    audioRecorder.cleanup()
                    isProcessing = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to save audio: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Audio Recorder
@MainActor
class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    func startRecording() {
        let audioFilename = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            isRecording = true
            recordingDuration = 0
            recordingURL = nil

            // Start timer to track duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let recorder = self.audioRecorder else { return }
                    self.recordingDuration = recorder.currentTime
                }
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
    }

    func playRecording() {
        guard let url = recordingURL else { return }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Failed to play recording: \(error)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
    }

    func deleteRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recordingDuration = 0
    }

    func cleanup() {
        stopRecording()
        stopPlayback()
        deleteRecording()
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if flag {
                recordingURL = recorder.url
            }
            isRecording = false
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }
}
