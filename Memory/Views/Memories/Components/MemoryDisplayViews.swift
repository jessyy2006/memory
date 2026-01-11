//
//  MemoryDisplayViews.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import SwiftUI
import AVKit
import Combine

// MARK: - Memory Card View
struct MemoryCardView: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: memory.type.icon)
                    .foregroundColor(.blue)

                Text(memory.type.title)
                    .font(.headline)

                Spacer()

                Text(formatDate(memory.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Content
            Group {
                switch memory.type {
                case .photo:
                    PhotoMemoryView(url: memory.content)

                case .video:
                    VideoMemoryView(url: memory.content, thumbnailURL: memory.thumbnailURL)

                case .note:
                    NoteMemoryView(text: memory.content)

                case .audio:
                    AudioMemoryView(url: memory.content, duration: memory.duration ?? 0)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .onAppear {
            print("📝 Displaying memory: \(memory.type.title) - \(memory.id)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Photo Memory View
struct PhotoMemoryView: View {
    let url: String
    @State private var image: UIImage?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(10)
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Failed to load image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            } else {
                ProgressView()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        print("🖼️ Loading image from: \(url)")
        guard let imageURL = URL(string: url) else {
            print("❌ Invalid image URL: \(url)")
            loadError = "Invalid URL"
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                if let loadedImage = UIImage(data: data) {
                    await MainActor.run {
                        image = loadedImage
                        print("✅ Image loaded successfully")
                    }
                } else {
                    await MainActor.run {
                        loadError = "Invalid image data"
                        print("❌ Failed to create UIImage from data")
                    }
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    print("❌ Failed to load image: \(error)")
                }
            }
        }
    }
}

// MARK: - Video Memory View
struct VideoMemoryView: View {
    let url: String
    let thumbnailURL: String?
    @State private var showPlayer = false

    var body: some View {
        Button(action: {
            print("🎬 Video play button tapped")
            print("🎬 Video URL: \(url)")
            showPlayer = true
        }) {
            ZStack {
                if let thumbURL = thumbnailURL {
                    AsyncImage(url: URL(string: thumbURL)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 200)
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 200)
                }

                // Play Overlay
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 60, height: 60)

                Image(systemName: "play.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showPlayer) {
            if let videoURL = URL(string: url) {
                VideoPlayerView(url: videoURL)
                    .onAppear {
                        print("🎬 Opening video player with URL: \(videoURL.absoluteString)")
                    }
            } else {
                Text("Invalid video URL")
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Video Player View
struct VideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if let player = player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView("Loading video...")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
            .onAppear {
                print("🎬 [VideoPlayer] Creating player for: \(url.absoluteString)")
                player = AVPlayer(url: url)
                player?.play()
                print("🎬 [VideoPlayer] Started playing")
            }
            .onDisappear {
                player?.pause()
                print("🎬 [VideoPlayer] Stopped playing")
            }
        }
    }
}

// MARK: - Note Memory View
struct NoteMemoryView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(10)
    }
}

// MARK: - Audio Memory View
struct AudioMemoryView: View {
    let url: String
    let duration: TimeInterval
    @StateObject private var audioPlayer = MemoryAudioPlayer()

    var body: some View {
        HStack(spacing: 16) {
            // Play Button
            Button(action: {
                print("🎵 Audio button tapped - isPlaying: \(audioPlayer.isPlaying)")
                if audioPlayer.isPlaying {
                    audioPlayer.stop()
                } else {
                    if let audioURL = URL(string: url) {
                        print("🎵 Playing audio from: \(audioURL.absoluteString)")
                        audioPlayer.play(url: audioURL)
                    } else {
                        print("❌ Invalid audio URL: \(url)")
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(audioPlayer.isPlaying ? Color.red : Color.blue)
                        .frame(width: 50, height: 50)

                    Image(systemName: audioPlayer.isPlaying ? "stop.fill" : "play.fill")
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Waveform Visualization
            HStack(spacing: 2) {
                ForEach(0..<30, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 3, height: CGFloat.random(in: 10...40))
                }
            }

            Spacer()

            // Duration
            Text(formatDuration(duration))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Memory Audio Player
@MainActor
class MemoryAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var audioPlayer: AVAudioPlayer?

    func play(url: URL) {
        print("🎵 [AudioPlayer] Starting playback...")
        // Download and play
        Task {
            do {
                print("🎵 [AudioPlayer] Downloading audio from: \(url.absoluteString)")
                let (data, _) = try await URLSession.shared.data(from: url)
                print("🎵 [AudioPlayer] Downloaded \(data.count) bytes")

                // Save to temp file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("temp-audio-\(UUID().uuidString).m4a")
                try data.write(to: tempURL)
                print("🎵 [AudioPlayer] Saved to temp file: \(tempURL.path)")

                // Play
                audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                let success = audioPlayer?.play() ?? false
                print("🎵 [AudioPlayer] Play started: \(success)")
                isPlaying = true
                print("🎵 [AudioPlayer] isPlaying set to true")
            } catch {
                print("❌ [AudioPlayer] Failed to play audio: \(error)")
                print("❌ [AudioPlayer] Error details: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        audioPlayer?.stop()
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }
}
