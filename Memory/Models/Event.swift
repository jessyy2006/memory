//
//  Event.swift
//  Memory
//
//  Created by Jessica Young on 1/10/26.
//

import Foundation
import SwiftData

/// Represents an event in the user's timeline
@Model
final class Event {
    var id: UUID
    var userId: UUID
    var name: String
    var eventDate: Date
    var startTime: Date?
    var endTime: Date?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        eventDate: Date,
        startTime: Date? = nil,
        endTime: Date? = nil,
        isActive: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.eventDate = eventDate
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Computed Properties

extension Event {
    /// Returns true if the event is in the future (event_date >= current date)
    var isUpcoming: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eventDay = calendar.startOfDay(for: eventDate)
        return eventDay >= today
    }

    /// Formatted date string for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: eventDate)
    }

    /// Formatted time range for display
    var formattedTimeRange: String? {
        guard let start = startTime, let end = endTime else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: end)
        return "\(startStr) - \(endStr)"
    }
}

// MARK: - Supabase Models

/// Database representation of an event for Supabase
struct EventRecord: Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let eventDate: Date
    let startTime: Date?
    let endTime: Date?
    let isActive: Bool
    let isUpcoming: Bool?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case eventDate = "event_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case isActive = "is_active"
        case isUpcoming = "is_upcoming"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Convert to SwiftData model
    func toEvent() -> Event {
        Event(
            id: id,
            userId: userId,
            name: name,
            eventDate: eventDate,
            startTime: startTime,
            endTime: endTime,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// For inserting new events into Supabase
struct EventInsert: Encodable {
    let id: String
    let userId: String
    let name: String
    let eventDate: String
    let startTime: String?
    let endTime: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case eventDate = "event_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case isActive = "is_active"
    }

    init(event: Event) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        self.id = event.id.uuidString
        self.userId = event.userId.uuidString
        self.name = event.name
        self.eventDate = dateFormatter.string(from: event.eventDate)
        self.startTime = event.startTime.map { timeFormatter.string(from: $0) }
        self.endTime = event.endTime.map { timeFormatter.string(from: $0) }
        self.isActive = event.isActive
    }
}

/// For updating events in Supabase
struct EventUpdate: Encodable {
    let name: String?
    let eventDate: String?
    let startTime: String?
    let endTime: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case eventDate = "event_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case isActive = "is_active"
    }
}

/// Response from stored procedures (start_event, stop_event)
struct EventActionResponse: Codable {
    let success: Bool
    let error: String?
    let eventId: UUID?
    let mostUpcomingEventId: UUID?
    let mostUpcomingEventDate: Date?

    enum CodingKeys: String, CodingKey {
        case success
        case error
        case eventId = "event_id"
        case mostUpcomingEventId = "most_upcoming_event_id"
        case mostUpcomingEventDate = "most_upcoming_event_date"
    }
}

/// Memory with event details (from the view)
struct MemoryWithEvent: Codable {
    let id: UUID
    let userId: UUID
    let type: String
    let content: String
    let thumbnailUrl: String?
    let duration: Double?
    let timestamp: Date
    let createdAt: Date
    let updatedAt: Date
    let eventId: UUID?
    let eventName: String?
    let eventDate: Date?
    let eventStartTime: Date?
    let eventEndTime: Date?
    let eventIsActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case content
        case thumbnailUrl = "thumbnail_url"
        case duration
        case timestamp
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case eventId = "event_id"
        case eventName = "event_name"
        case eventDate = "event_date"
        case eventStartTime = "event_start_time"
        case eventEndTime = "event_end_time"
        case eventIsActive = "event_is_active"
    }
}
