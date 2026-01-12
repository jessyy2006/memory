//
//  MemoryPlaybackView.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import SwiftUI
import SwiftData

struct MemoryPlaybackView: View {
    @Environment(\.dismiss) private var dismiss
    let memoryService: MemoryService
    let userId: UUID
    let eventName: String? // Optional event name

    @State private var showDeleteConfirmation = false
    @State private var memoryToDelete: Memory?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if memoryService.memories.isEmpty {
                    // Empty State
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Memories Yet")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Start capturing your moments")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 100)
                } else {
                    // Memory Timeline
                    LazyVStack(spacing: 16) {
                        ForEach(memoryService.memories) { memory in
                            VStack {
                                MemoryCardView(memory: memory)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    memoryToDelete = memory
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            print("📺 MemoryPlaybackView appeared with \(memoryService.memories.count) memories")
            print("📺 Event name: \(eventName ?? "none")")
        }
        .navigationTitle(eventName ?? "Your Memories")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await memoryService.syncMemories(userId: userId)
        }
        .alert("Delete Memory", isPresented: $showDeleteConfirmation, presenting: memoryToDelete) { memory in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    try? await memoryService.deleteMemory(memory)
                }
            }
        } message: { _ in
            Text("Are you sure you want to delete this memory? This action cannot be undone.")
        }
    }
}

#Preview {
    @Previewable @State var modelContext = try! ModelContainer(
        for: Memory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ).mainContext

    return NavigationStack {
        MemoryPlaybackView(
            memoryService: MemoryService(modelContext: modelContext),
            userId: UUID(),
            eventName: "Test Event"
        )
    }
}
