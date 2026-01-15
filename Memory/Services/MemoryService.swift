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

    /// Fetch memories for a specific event from local storage
    /// - Parameters:
    ///   - userId: The user ID
    ///   - eventId: The event ID to filter by (REQUIRED for data isolation)
    func fetchLocalMemories(userId: UUID, eventId: UUID) {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { memory in
                memory.userId == userId && memory.eventId == eventId
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            memories = try modelContext.fetch(descriptor)
            print("✅ Fetched \(memories.count) local memories for user \(userId) in event \(eventId)")
        } catch {
            self.error = error
            print("❌ Error fetching local memories: \(error)")
        }
    }

    /// Sync memories for a specific event from Supabase to local storage
    /// - Parameters:
    ///   - userId: The user ID
    ///   - eventId: The event ID to sync (REQUIRED for data isolation)
    func syncMemories(userId: UUID, eventId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let remoteMemories = try await supabaseManager.fetchMemories(userId: userId, eventId: eventId)

            // Clear local cache for this specific event
            let descriptor = FetchDescriptor<Memory>(
                predicate: #Predicate { memory in
                    memory.userId == userId && memory.eventId == eventId
                }
            )
            let localMemories = try modelContext.fetch(descriptor)
            for memory in localMemories {
                modelContext.delete(memory)
            }

            // Insert remote memories for this event
            for remoteMemory in remoteMemories {
                let memory = Memory(
                    id: remoteMemory.id,
                    userId: remoteMemory.userId,
                    eventId: remoteMemory.eventId,
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
            fetchLocalMemories(userId: userId, eventId: eventId)

        } catch {
            self.error = error
            print("❌ Error syncing memories: \(error)")
        }
    }

    // MARK: - Deduplication

    /// Check if a memory with the same content already exists in the event
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - content: The memory content (file URL or note text)
    /// - Returns: True if a duplicate exists, false otherwise
    private func isDuplicate(eventId: UUID, content: String) -> Bool {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { memory in
                memory.eventId == eventId && memory.content == content
            }
        )

        do {
            let duplicates = try modelContext.fetch(descriptor)
            if !duplicates.isEmpty {
                print("⚠️ Duplicate memory detected: content '\(content)' already exists in event \(eventId)")
                return true
            }
            return false
        } catch {
            print("❌ Error checking for duplicates: \(error)")
            return false  // If check fails, allow the insert
        }
    }

    // MARK: - Create Memories

    /// Create a photo memory
    /// - Parameters:
    ///   - userId: The user ID
    ///   - imageData: The image data
    ///   - eventId: The event ID (REQUIRED - every memory must belong to an event)
    func createPhotoMemory(userId: UUID, imageData: Data, eventId: UUID) async throws {
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

        // Check for duplicates BEFORE creating the memory
        if isDuplicate(eventId: eventId, content: imageURL) {
            print("⚠️ [Photo] Duplicate detected - skipping creation")
            throw NSError(domain: "MemoryService", code: 409,
                userInfo: [NSLocalizedDescriptionKey: "This photo already exists in this event"])
        }

        // Create memory record
        let memory = Memory(
            userId: userId,
            eventId: eventId,
            type: .photo,
            content: imageURL
        )

        // Save to Supabase
        try await supabaseManager.insertMemory(memory: memory)

        // Save locally
        modelContext.insert(memory)
        try modelContext.save()

        // Refresh list
        fetchLocalMemories(userId: userId, eventId: eventId)
    }

    /// Create a video memory
    /// - Parameters:
    ///   - userId: The user ID
    ///   - videoURL: The video URL
    ///   - eventId: The event ID (REQUIRED - every memory must belong to an event)
    func createVideoMemory(userId: UUID, videoURL: URL, eventId: UUID) async throws {
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

        // Check for duplicates BEFORE creating the memory
        if isDuplicate(eventId: eventId, content: videoURLString) {
            print("⚠️ [Video] Duplicate detected - skipping creation")
            throw NSError(domain: "MemoryService", code: 409,
                userInfo: [NSLocalizedDescriptionKey: "This video already exists in this event"])
        }

        // Create memory record
        let memory = Memory(
            userId: userId,
            eventId: eventId,
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
        fetchLocalMemories(userId: userId, eventId: eventId)
    }

    /// Create a note memory
    /// - Parameters:
    ///   - userId: The user ID
    ///   - noteText: The note text
    ///   - eventId: The event ID (REQUIRED - every memory must belong to an event)
    func createNoteMemory(userId: UUID, noteText: String, eventId: UUID) async throws {
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

        // Check for duplicates BEFORE creating the memory
        if isDuplicate(eventId: eventId, content: noteText) {
            print("⚠️ [Note] Duplicate detected - skipping creation")
            throw NSError(domain: "MemoryService", code: 409,
                userInfo: [NSLocalizedDescriptionKey: "This note already exists in this event"])
        }

        // Create memory record
        let memory = Memory(
            userId: userId,
            eventId: eventId,
            type: .note,
            content: noteText
        )

        // Save to Supabase
        try await supabaseManager.insertMemory(memory: memory)

        // Save locally
        modelContext.insert(memory)
        try modelContext.save()

        // Refresh list
        fetchLocalMemories(userId: userId, eventId: eventId)
    }

    /// Create an audio memory
    /// - Parameters:
    ///   - userId: The user ID
    ///   - audioURL: The audio URL
    ///   - eventId: The event ID (REQUIRED - every memory must belong to an event)
    func createAudioMemory(userId: UUID, audioURL: URL, eventId: UUID) async throws {
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

        // Check for duplicates BEFORE creating the memory
        if isDuplicate(eventId: eventId, content: audioURLString) {
            print("⚠️ [Audio] Duplicate detected - skipping creation")
            throw NSError(domain: "MemoryService", code: 409,
                userInfo: [NSLocalizedDescriptionKey: "This audio already exists in this event"])
        }

        // Create memory record
        let memory = Memory(
            userId: userId,
            eventId: eventId,
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
        fetchLocalMemories(userId: userId, eventId: eventId)
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

        // Refresh list (need to pass eventId - get from memory before deletion)
        let eventId = memory.eventId
        fetchLocalMemories(userId: memory.userId, eventId: eventId)
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
