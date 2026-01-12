//
//  Memory.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import Foundation
import SwiftData

/// Represents a memory item in the user's timeline
@Model
final class Memory {
    var id: UUID
    var userId: UUID
    var eventId: UUID? // Links to an event
    var type: MemoryType
    var content: String // For notes, this is the text; for media, this is the URL
    var thumbnailURL: String? // Thumbnail for videos/images
    var duration: TimeInterval? // For audio/video
    var timestamp: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        eventId: UUID? = nil,
        type: MemoryType,
        content: String,
        thumbnailURL: String? = nil,
        duration: TimeInterval? = nil,
        timestamp: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.eventId = eventId
        self.type = type
        self.content = content
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Type of memory content
enum MemoryType: String, Codable {
    case photo
    case video
    case note
    case audio

    var icon: String {
        switch self {
        case .photo: return "photo.fill"
        case .video: return "video.fill"
        case .note: return "note.text"
        case .audio: return "waveform"
        }
    }

    var title: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .note: return "Note"
        case .audio: return "Voice Memo"
        }
    }
}

// MARK: - Supabase Models

/// Database representation of a memory for Supabase
struct MemoryRecord: Codable {
    let id: UUID
    let userId: UUID
    let eventId: UUID?
    let type: String
    let content: String
    let thumbnailUrl: String?
    let duration: Double?
    let timestamp: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventId = "event_id"
        case type
        case content
        case thumbnailUrl = "thumbnail_url"
        case duration
        case timestamp
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// For inserting new memories into Supabase
struct MemoryInsert: Encodable {
    let id: String
    let userId: String
    let eventId: String?
    let type: String
    let content: String
    let thumbnailUrl: String?
    let duration: Double?
    let timestamp: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventId = "event_id"
        case type
        case content
        case thumbnailUrl = "thumbnail_url"
        case duration
        case timestamp
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(memory: Memory) {
        let formatter = ISO8601DateFormatter()
        self.id = memory.id.uuidString
        self.userId = memory.userId.uuidString
        self.eventId = memory.eventId?.uuidString
        self.type = memory.type.rawValue
        self.content = memory.content
        self.thumbnailUrl = memory.thumbnailURL
        self.duration = memory.duration
        self.timestamp = formatter.string(from: memory.timestamp)
        self.createdAt = formatter.string(from: memory.createdAt)
        self.updatedAt = formatter.string(from: memory.updatedAt)
    }
}
