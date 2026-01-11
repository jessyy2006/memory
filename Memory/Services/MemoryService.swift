//
//  MemoryService.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import Auth

/// Service class for managing memories (CRUD operations, media handling)
@Observable
class MemoryService {
    private let supabaseManager = SupabaseManager.shared
    private let modelContext: ModelContext
    private(set) var memories: [Memory] = []
    private(set) var isLoading: Bool = false
    private(set) var error: Error?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch Memories

    /// Fetch all memories for the current user from local storage
    func fetchLocalMemories(userId: UUID) {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            memories = try modelContext.fetch(descriptor)
            print("✅ Fetched \(memories.count) local memories for user \(userId)")
        } catch {
            self.error = error
            print("❌ Error fetching local memories: \(error)")
        }
    }

    /// Sync memories from Supabase to local storage
    func syncMemories(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let remoteMemories = try await supabaseManager.fetchMemories(userId: userId)

            // Clear local cache and insert fresh data
            let descriptor = FetchDescriptor<Memory>(
                predicate: #Predicate { $0.userId == userId }
            )
            let localMemories = try modelContext.fetch(descriptor)
            for memory in localMemories {
                modelContext.delete(memory)
            }

            // Insert remote memories
            for remoteMemory in remoteMemories {
                let memory = Memory(
                    id: remoteMemory.id,
                    userId: remoteMemory.userId,
                    type: MemoryType(rawValue: remoteMemory.type) ?? .note,
                    content: remoteMemory.content,
                    thumbnailURL: remoteMemory.thumbnailUrl,
                    duration: remoteMemory.duration,
                    timestamp: remoteMemory.timestamp,
                    createdAt: remoteMemory.createdAt,
                    updatedAt: remoteMemory.updatedAt
                )
                modelContext.insert(memory)
            }

            try modelContext.save()
            fetchLocalMemories(userId: userId)

        } catch {
            self.error = error
            print("❌ Error syncing memories: \(error)")
        }
    }

    // MARK: - Create Memories

    /// Create a photo memory
    func createPhotoMemory(userId: UUID, imageData: Data) async throws {
        isLoading = true
        defer { isLoading = false }

        // Verify session before creating
        print("🔍 [Photo] Checking Supabase session...")
        let session = try? await supabaseManager.getCurrentSession()
        if let session = session {
            print("✅ [Photo] Active session found for user: \(session.user.id)")
            print("📝 [Photo] Attempting to create memory for user: \(userId)")
        } else {
            print("❌ [Photo] No active Supabase session!")
            throw NSError(domain: "MemoryService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No active session. Please log in again."])
        }

        // Upload to Supabase Storage
        let imageURL = try await supabaseManager.uploadMemoryMedia(
            userId: userId,
            data: imageData,
            type: .photo
        )

        // Create memory record
        let memory = Memory(
            userId: userId,
            type: .photo,
            content: imageURL
        )

        // Save to Supabase
        try await supabaseManager.insertMemory(memory: memory)

        // Save locally
        modelContext.insert(memory)
        try modelContext.save()

        // Refresh list
        fetchLocalMemories(userId: userId)
    }

    /// Create a video memory
    func createVideoMemory(userId: UUID, videoURL: URL) async throws {
        isLoading = true
        defer { isLoading = false }

        // Verify session before creating
        print("🔍 [Video] Checking Supabase session...")
        let session = try? await supabaseManager.getCurrentSession()
        if let session = session {
            print("✅ [Video] Active session found for user: \(session.user.id)")
            print("📝 [Video] Attempting to create memory for user: \(userId)")
        } else {
            print("❌ [Video] No active Supabase session!")
            throw NSError(domain: "MemoryService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No active session. Please log in again."])
        }

        // Read video data
        let videoData = try Data(contentsOf: videoURL)

        // Generate thumbnail
        let thumbnail = try await generateVideoThumbnail(from: videoURL)
        let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) ?? Data()

        // Get video duration
        let duration = try await getVideoDuration(from: videoURL)

        // Upload video to Supabase Storage
        let videoURLString = try await supabaseManager.uploadMemoryMedia(
            userId: userId,
            data: videoData,
            type: .video
        )

        // Upload thumbnail
        let thumbnailURLString = try await supabaseManager.uploadMemoryMedia(
            userId: userId,
            data: thumbnailData,
            type: .photo,
            isThumbnail: true
        )

        // Create memory record
        let memory = Memory(
            userId: userId,
            type: .video,
            content: videoURLString,
            thumbnailURL: thumbnailURLString,
            duration: duration
        )

        // Save to Supabase
        try await supabaseManager.insertMemory(memory: memory)

        // Save locally
        modelContext.insert(memory)
        try modelContext.save()

        // Refresh list
        fetchLocalMemories(userId: userId)
    }

    /// Create a note memory
    func createNoteMemory(userId: UUID, noteText: String) async throws {
        isLoading = true
        defer { isLoading = false }

        // Verify session before inserting
        print("🔍 Checking Supabase session...")
        let session = try? await supabaseManager.getCurrentSession()
        if let session = session {
            print("✅ Active session found for user: \(session.user.id)")
            print("📝 Attempting to create memory for user: \(userId)")
        } else {
            print("❌ No active Supabase session!")
            throw NSError(domain: "MemoryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active session. Please log in again."])
        }

        // Create memory record
        let memory = Memory(
            userId: userId,
            type: .note,
            content: noteText
        )

        // Save to Supabase
        try await supabaseManager.insertMemory(memory: memory)

        // Save locally
        modelContext.insert(memory)
        try modelContext.save()

        // Refresh list
        fetchLocalMemories(userId: userId)
    }

    /// Create an audio memory
    func createAudioMemory(userId: UUID, audioURL: URL) async throws {
        isLoading = true
        defer { isLoading = false }

        // Verify session before creating
        print("🔍 [Audio] Checking Supabase session...")
        let session = try? await supabaseManager.getCurrentSession()
        if let session = session {
            print("✅ [Audio] Active session found for user: \(session.user.id)")
            print("📝 [Audio] Attempting to create memory for user: \(userId)")
        } else {
            print("❌ [Audio] No active Supabase session!")
            throw NSError(domain: "MemoryService", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No active session. Please log in again."])
        }

        // Read audio data
        let audioData = try Data(contentsOf: audioURL)

        // Get audio duration
        let duration = try await getAudioDuration(from: audioURL)

        // Upload audio to Supabase Storage
        let audioURLString = try await supabaseManager.uploadMemoryMedia(
            userId: userId,
            data: audioData,
            type: .audio
        )

        // Create memory record
        let memory = Memory(
            userId: userId,
            type: .audio,
            content: audioURLString,
            duration: duration
        )

        // Save to Supabase
        try await supabaseManager.insertMemory(memory: memory)

        // Save locally
        modelContext.insert(memory)
        try modelContext.save()

        // Refresh list
        fetchLocalMemories(userId: userId)
    }

    // MARK: - Delete Memory

    func deleteMemory(_ memory: Memory) async throws {
        isLoading = true
        defer { isLoading = false }

        // Delete from Supabase
        try await supabaseManager.deleteMemory(memoryId: memory.id)

        // Delete media files if needed
        if memory.type != .note {
            try? await supabaseManager.deleteMemoryMedia(url: memory.content)
        }
        if let thumbnailURL = memory.thumbnailURL {
            try? await supabaseManager.deleteMemoryMedia(url: thumbnailURL)
        }

        // Delete locally
        modelContext.delete(memory)
        try modelContext.save()

        // Refresh list
        fetchLocalMemories(userId: memory.userId)
    }

    // MARK: - Helper Methods

    private func generateVideoThumbnail(from url: URL) async throws -> UIImage {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 1, preferredTimescale: 60)
        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)

        return UIImage(cgImage: cgImage)
    }

    private func getVideoDuration(from url: URL) async throws -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private func getAudioDuration(from url: URL) async throws -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}
