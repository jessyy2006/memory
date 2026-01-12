//
//  NoteEditorView.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import SwiftUI

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let memoryService: MemoryService
    let userId: UUID
    let eventId: UUID?
    let onComplete: () -> Void

    @State private var noteText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Write a Note")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 32)

                // Text Editor
                ZStack(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("Capture your thoughts...")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $noteText)
                        .focused($isTextFieldFocused)
                        .padding(8)
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal)

                // Character Count
                HStack {
                    Spacer()
                    Text("\(noteText.count) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }

                Spacer()

                // Save Button
                Button(action: saveNote) {
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
                .background(noteText.isEmpty ? Color.gray : Color.green)
                .cornerRadius(15)
                .padding(.horizontal)
                .padding(.bottom, 32)
                .disabled(noteText.isEmpty || isProcessing)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }

    private func saveNote() {
        guard !noteText.isEmpty else {
            errorMessage = "Please enter some text"
            return
        }

        isProcessing = true
        Task {
            do {
                try await memoryService.createNoteMemory(userId: userId, noteText: noteText, eventId: eventId)
                await MainActor.run {
                    isProcessing = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to save note: \(error.localizedDescription)"
                }
            }
        }
    }
}
