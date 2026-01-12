//
//  MediaTypePickerView.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import SwiftUI
import SwiftData

struct MediaTypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let memoryService: MemoryService
    let userId: UUID
    let eventId: UUID?

    @State private var showImagePicker = false
    @State private var showVideoPicker = false
    @State private var showNoteEditor = false
    @State private var showAudioRecorder = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Choose Memory Type")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 32)

                VStack(spacing: 16) {
                    // Photo Option
                    MediaTypeButton(
                        icon: "photo.fill",
                        title: "Take Photo",
                        description: "Capture a moment",
                        gradient: [.orange, .pink]
                    ) {
                        showImagePicker = true
                    }

                    // Video Option
                    MediaTypeButton(
                        icon: "video.fill",
                        title: "Record Video",
                        description: "Capture moving memories",
                        gradient: [.purple, .blue]
                    ) {
                        showVideoPicker = true
                    }

                    // Note Option
                    MediaTypeButton(
                        icon: "note.text",
                        title: "Write Note",
                        description: "Capture your thoughts",
                        gradient: [.green, .mint]
                    ) {
                        showNoteEditor = true
                    }

                    // Audio Option
                    MediaTypeButton(
                        icon: "waveform",
                        title: "Voice Memo",
                        description: "Record your voice",
                        gradient: [.red, .orange]
                    ) {
                        showAudioRecorder = true
                    }
                }
                .padding(.horizontal, 24)

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
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(memoryService: memoryService, userId: userId, eventId: eventId) {
                    dismiss()
                }
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPickerView(memoryService: memoryService, userId: userId, eventId: eventId) {
                    dismiss()
                }
            }
            .sheet(isPresented: $showNoteEditor) {
                NoteEditorView(memoryService: memoryService, userId: userId, eventId: eventId) {
                    dismiss()
                }
            }
            .sheet(isPresented: $showAudioRecorder) {
                AudioRecorderView(memoryService: memoryService, userId: userId, eventId: eventId) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Media Type Button
struct MediaTypeButton: View {
    let icon: String
    let title: String
    let description: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.white)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(15)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    @Previewable @State var modelContext = try! ModelContainer(
        for: Memory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ).mainContext

    return MediaTypePickerView(
        memoryService: MemoryService(modelContext: modelContext),
        userId: UUID(),
        eventId: nil
    )
}
