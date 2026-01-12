//
//  VideoPickerView.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import SwiftUI
import PhotosUI
import AVKit

struct VideoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let memoryService: MemoryService
    let userId: UUID
    let eventId: UUID?
    let onComplete: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let url = videoURL {
                    // Video Preview
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 400)
                        .cornerRadius(15)
                        .padding()

                    // Save Button
                    Button(action: saveVideo) {
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
                    .background(Color.blue)
                    .cornerRadius(15)
                    .padding(.horizontal)
                    .disabled(isProcessing)

                } else {
                    // Selection Options
                    VStack(spacing: 20) {
                        Text("Add a Video")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top, 40)

                        // Camera Button
                        Button(action: { showCamera = true }) {
                            HStack {
                                Image(systemName: "video.fill")
                                    .font(.title2)
                                Text("Record Video")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(15)
                        }
                        .padding(.horizontal)

                        // Photo Library Picker
                        PhotosPicker(selection: $selectedItem, matching: .videos) {
                            HStack {
                                Image(systemName: "film.fill")
                                    .font(.title2)
                                Text("Choose from Library")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(15)
                        }
                        .padding(.horizontal)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                VideoCameraView(videoURL: $videoURL)
            }
            .onChange(of: selectedItem) { _, newValue in
                Task {
                    if let movie = try? await newValue?.loadTransferable(type: VideoTransferable.self) {
                        videoURL = movie.url
                    }
                }
            }
        }
    }

    private func saveVideo() {
        guard let url = videoURL else {
            errorMessage = "No video selected"
            return
        }

        isProcessing = true
        Task {
            do {
                try await memoryService.createVideoMemory(userId: userId, videoURL: url, eventId: eventId)
                await MainActor.run {
                    isProcessing = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to save video: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Video Camera View
struct VideoCameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var videoURL: URL?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoCameraView

        init(_ parent: VideoCameraView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = info[.mediaURL] as? URL {
                parent.videoURL = url
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Video Transferable
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "video-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
