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
    /// Returns true if the event hasn't ended yet (local calculation)
    ///
    /// **Note**: This is different from the database's `is_upcoming` field!
    /// - Database `is_upcoming`: Only true for THE SINGLE most upcoming event (only one event can have this)
    /// - This computed property: True for ANY event that hasn't ended yet (multiple events can be true)
    ///
    /// Logic:
    /// - If event has an end_time: checks if end_time hasn't passed
    /// - If event has no end_time: checks if event_date hasn't passed
    var isUpcoming: Bool {
        let now = Date()

        // If event has an end time, use it to determine if event is over
        if let endTime = endTime {
            // Combine event date + end time
            let calendar = Calendar.current
            let eventDay = calendar.startOfDay(for: eventDate)

            // Extract hour and minute from endTime
            let endHour = calendar.component(.hour, from: endTime)
            let endMinute = calendar.component(.minute, from: endTime)

            // Create full end datetime
            guard let eventEndDateTime = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: eventDay) else {
                // Fallback to date-only comparison
                return calendar.startOfDay(for: eventDate) >= calendar.startOfDay(for: now)
            }

            // Event is upcoming if end time hasn't passed yet (FIXED: use > instead of >=)
            return eventEndDateTime > now
        } else {
            // No end time - use date-only comparison
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let eventDay = calendar.startOfDay(for: eventDate)
            return eventDay >= today
        }
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
struct EventRecord: Codable, Hashable {
    let id: UUID
    let userId: UUID
    let name: String
    let eventDate: Date
    let startTime: Date?
    let endTime: Date?
    let isActive: Bool
    let isUpcoming: Bool?
    let isFuture: Bool?
    let isEnded: Bool
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
        case isFuture = "is_future"
        case isEnded = "is_ended"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Custom decoder to handle DATE and TIMESTAMPTZ formats from Supabase
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isUpcoming = try container.decodeIfPresent(Bool.self, forKey: .isUpcoming)
        isFuture = try container.decodeIfPresent(Bool.self, forKey: .isFuture)
        isEnded = try container.decode(Bool.self, forKey: .isEnded)

        // Decode eventDate (DATE format: "2026-01-12")
        // Use user's local timezone so "2026-01-12" displays as "2026-01-12" in their region
        let eventDateString = try container.decode(String.self, forKey: .eventDate)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current // Use user's local timezone
        guard let date = dateFormatter.date(from: eventDateString) else {
            throw DecodingError.dataCorruptedError(forKey: .eventDate, in: container, debugDescription: "Invalid date format: \(eventDateString)")
        }
        eventDate = date

        // Decode timestamps (ISO8601 format with fractional seconds - stored in UTC)
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Decode startTime (TIMESTAMPTZ stored in UTC, converted to user's local time)
        if let startTimeString = try container.decodeIfPresent(String.self, forKey: .startTime) {
            guard let utcTime = iso8601Formatter.date(from: startTimeString) else {
                throw DecodingError.dataCorruptedError(forKey: .startTime, in: container, debugDescription: "Invalid timestamp format: \(startTimeString)")
            }
            // Store as Date (Swift Date is always UTC internally, displays in local time)
            startTime = utcTime
        } else {
            startTime = nil
        }

        // Decode endTime (TIMESTAMPTZ stored in UTC, converted to user's local time)
        if let endTimeString = try container.decodeIfPresent(String.self, forKey: .endTime) {
            guard let utcTime = iso8601Formatter.date(from: endTimeString) else {
                throw DecodingError.dataCorruptedError(forKey: .endTime, in: container, debugDescription: "Invalid timestamp format: \(endTimeString)")
            }
            // Store as Date (Swift Date is always UTC internally, displays in local time)
            endTime = utcTime
        } else {
            endTime = nil
        }

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        guard let created = iso8601Formatter.date(from: createdAtString) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: container, debugDescription: "Invalid timestamp format: \(createdAtString)")
        }
        createdAt = created

        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        guard let updated = iso8601Formatter.date(from: updatedAtString) else {
            throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: container, debugDescription: "Invalid timestamp format: \(updatedAtString)")
        }
        updatedAt = updated
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
    let isEnded: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case eventDate = "event_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case isActive = "is_active"
        case isEnded = "is_ended"
    }

    init(event: Event) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // ISO8601 formatter for TIMESTAMPTZ (UTC)
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        self.id = event.id.uuidString
        self.userId = event.userId.uuidString
        self.name = event.name
        self.eventDate = dateFormatter.string(from: event.eventDate)

        // Convert local time to UTC for storage
        // The user selects a time in their local timezone (e.g., 3 PM PST)
        // We need to combine it with the event date and convert to UTC
        if let startTime = event.startTime {
            // Combine event date + start time in user's local timezone
            let calendar = Calendar.current
            let eventDay = calendar.startOfDay(for: event.eventDate)
            let hour = calendar.component(.hour, from: startTime)
            let minute = calendar.component(.minute, from: startTime)
            let second = calendar.component(.second, from: startTime)

            if let localDateTime = calendar.date(bySettingHour: hour, minute: minute, second: second, of: eventDay) {
                // Convert to UTC and format as ISO8601
                self.startTime = iso8601Formatter.string(from: localDateTime)
            } else {
                self.startTime = nil
            }
        } else {
            self.startTime = nil
        }

        if let endTime = event.endTime {
            // Combine event date + end time in user's local timezone
            let calendar = Calendar.current
            let eventDay = calendar.startOfDay(for: event.eventDate)
            let hour = calendar.component(.hour, from: endTime)
            let minute = calendar.component(.minute, from: endTime)
            let second = calendar.component(.second, from: endTime)

            if let localDateTime = calendar.date(bySettingHour: hour, minute: minute, second: second, of: eventDay) {
                // Convert to UTC and format as ISO8601
                self.endTime = iso8601Formatter.string(from: localDateTime)
            } else {
                self.endTime = nil
            }
        } else {
            self.endTime = nil
        }

        self.isActive = event.isActive
        self.isEnded = false  // New events are not ended
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

    // Custom decoder to handle DATE format from Supabase
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        eventId = try container.decodeIfPresent(UUID.self, forKey: .eventId)
        mostUpcomingEventId = try container.decodeIfPresent(UUID.self, forKey: .mostUpcomingEventId)

        // Decode mostUpcomingEventDate (DATE format: "2026-01-12" or null)
        // Use user's local timezone
        if let dateString = try container.decodeIfPresent(String.self, forKey: .mostUpcomingEventDate) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            mostUpcomingEventDate = dateFormatter.date(from: dateString)
        } else {
            mostUpcomingEventDate = nil
        }
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

    // Custom decoder to handle DATE and TIME formats from Supabase
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        eventId = try container.decodeIfPresent(UUID.self, forKey: .eventId)
        eventName = try container.decodeIfPresent(String.self, forKey: .eventName)
        eventIsActive = try container.decodeIfPresent(Bool.self, forKey: .eventIsActive)

        // Decode timestamps (ISO8601 format with fractional seconds)
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let timestampString = try container.decode(String.self, forKey: .timestamp)
        guard let ts = iso8601Formatter.date(from: timestampString) else {
            throw DecodingError.dataCorruptedError(forKey: .timestamp, in: container, debugDescription: "Invalid timestamp format: \(timestampString)")
        }
        timestamp = ts

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        guard let created = iso8601Formatter.date(from: createdAtString) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: container, debugDescription: "Invalid timestamp format: \(createdAtString)")
        }
        createdAt = created

        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        guard let updated = iso8601Formatter.date(from: updatedAtString) else {
            throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: container, debugDescription: "Invalid timestamp format: \(updatedAtString)")
        }
        updatedAt = updated

        // Decode eventDate (DATE format: "2026-01-12" or null)
        // Use user's local timezone
        if let eventDateString = try container.decodeIfPresent(String.self, forKey: .eventDate) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            eventDate = dateFormatter.date(from: eventDateString)
        } else {
            eventDate = nil
        }

        // Decode eventStartTime (TIMESTAMPTZ format - stored in UTC)
        if let startTimeString = try container.decodeIfPresent(String.self, forKey: .eventStartTime) {
            guard let utcTime = iso8601Formatter.date(from: startTimeString) else {
                throw DecodingError.dataCorruptedError(forKey: .eventStartTime, in: container, debugDescription: "Invalid timestamp format: \(startTimeString)")
            }
            // Store as Date (Swift Date is always UTC internally, displays in local time)
            eventStartTime = utcTime
        } else {
            eventStartTime = nil
        }

        // Decode eventEndTime (TIMESTAMPTZ format - stored in UTC)
        if let endTimeString = try container.decodeIfPresent(String.self, forKey: .eventEndTime) {
            guard let utcTime = iso8601Formatter.date(from: endTimeString) else {
                throw DecodingError.dataCorruptedError(forKey: .eventEndTime, in: container, debugDescription: "Invalid timestamp format: \(endTimeString)")
            }
            // Store as Date (Swift Date is always UTC internally, displays in local time)
            eventEndTime = utcTime
        } else {
            eventEndTime = nil
        }
    }
}
