//
//  EventService.swift
//  Memory
//
//  Created by Jessica Young on 1/10/26.
//

import Foundation
import Supabase

// MARK: - RPC Parameter Types

nonisolated private struct GetEventsSortedParams: Encodable, Sendable {
    let p_user_id: String
}

nonisolated private struct GetMostUpcomingEventParams: Encodable, Sendable {
    let p_user_id: String
}

nonisolated private struct StartEventParams: Encodable, Sendable {
    let p_event_id: String
    let p_user_id: String
}

nonisolated private struct StopEventParams: Encodable, Sendable {
    let p_event_id: String
    let p_user_id: String
}

/// Service for managing events in Supabase
@Observable
final class EventService {
    // MARK: - Properties

    private let supabase = SupabaseManager.shared.client

    // MARK: - CRUD Operations

    /// Creates a new event
    /// - Parameter event: The event to create
    /// - Returns: The created event record
    func createEvent(_ event: Event) async throws -> EventRecord {
        print("📝 [EventService] Creating event: \(event.name)")
        print("📝 [EventService] Event date: \(event.eventDate)")
        print("📝 [EventService] User ID: \(event.userId)")

        let insert = EventInsert(event: event)
        print("📝 [EventService] EventInsert: \(insert)")

        let response: EventRecord = try await supabase
            .from(SupabaseConfig.Tables.events)
            .insert(insert)
            .select()
            .single()
            .execute()
            .value

        print("✅ [EventService] Event created in Supabase: ID=\(response.id), Name=\(response.name)")
        return response
    }

    /// Fetches all events for the current user, sorted chronologically
    /// - Returns: Array of event records sorted with upcoming events first (soonest first), then past events
    func fetchEvents() async throws -> [EventRecord] {
        let userId = try await SupabaseManager.shared.getCurrentUserId()
        print("🔍 [EventService] Fetching events for user: \(userId)")

        var events: [EventRecord]

        do {
            // Try using the stored procedure first
            print("🔍 [EventService] Calling RPC: \(SupabaseConfig.Functions.getEventsSorted)")
            events = try await supabase
                .rpc(SupabaseConfig.Functions.getEventsSorted, params: GetEventsSortedParams(p_user_id: userId.uuidString))
                .execute()
                .value

            print("✅ [EventService] RPC returned \(events.count) events")
        } catch {
            print("⚠️ [EventService] RPC failed: \(error.localizedDescription)")
            print("⚠️ [EventService] Falling back to direct query...")

            // Fallback: Direct SELECT query
            events = try await supabase
                .from(SupabaseConfig.Tables.events)
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("event_date", ascending: true)
                .execute()
                .value

            print("✅ [EventService] Direct query returned \(events.count) events")
        }

        // Sort events: upcoming first (soonest first), then past events (most recent first)
        let today = Calendar.current.startOfDay(for: Date())
        let sortedEvents = events.sorted { event1, event2 in
            let date1 = Calendar.current.startOfDay(for: event1.eventDate)
            let date2 = Calendar.current.startOfDay(for: event2.eventDate)

            let isEvent1Upcoming = date1 >= today
            let isEvent2Upcoming = date2 >= today

            // Both upcoming or both past - sort by date
            if isEvent1Upcoming == isEvent2Upcoming {
                return isEvent1Upcoming ? date1 < date2 : date1 > date2
            }

            // One upcoming, one past - upcoming comes first
            return isEvent1Upcoming
        }

        print("📅 [EventService] Events sorted: upcoming first (soonest → latest), then past")
        return sortedEvents
    }

    /// Fetches a single event by ID
    /// - Parameter id: The event ID
    /// - Returns: The event record
    func fetchEvent(id: UUID) async throws -> EventRecord {
        let response: EventRecord = try await supabase
            .from(SupabaseConfig.Tables.events)
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        return response
    }

    /// Updates an existing event
    /// - Parameters:
    ///   - id: The event ID
    ///   - update: The fields to update
    /// - Returns: The updated event record
    func updateEvent(id: UUID, update: EventUpdate) async throws -> EventRecord {
        let response: EventRecord = try await supabase
            .from(SupabaseConfig.Tables.events)
            .update(update)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value

        return response
    }

    /// Deletes an event
    /// - Parameter id: The event ID
    func deleteEvent(id: UUID) async throws {
        try await supabase
            .from(SupabaseConfig.Tables.events)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Event Activation Logic

    /// Gets the most upcoming event (event_date >= current date)
    /// - Returns: The most upcoming event, or nil if none found
    func getMostUpcomingEvent() async throws -> EventRecord? {
        let userId = try await SupabaseManager.shared.getCurrentUserId()

        let response: [EventRecord] = try await supabase
            .rpc(SupabaseConfig.Functions.getMostUpcomingEvent, params: GetMostUpcomingEventParams(p_user_id: userId.uuidString))
            .execute()
            .value

        return response.first
    }

    /// Starts an event (sets is_active = true)
    /// - Parameter eventId: The event ID to activate
    /// - Returns: Result indicating success or failure with error details
    /// - Throws: Error if the event cannot be started
    func startEvent(eventId: UUID) async throws -> EventActionResponse {
        let userId = try await SupabaseManager.shared.getCurrentUserId()

        print("🎬 [EventService] startEvent() called")
        print("   - Event ID: \(eventId)")
        print("   - User ID: \(userId)")
        print("📞 [EventService] Calling RPC: start_event")

        let response: EventActionResponse = try await supabase
            .rpc(SupabaseConfig.Functions.startEvent, params: StartEventParams(p_event_id: eventId.uuidString, p_user_id: userId.uuidString))
            .execute()
            .value

        print("📬 [EventService] RPC Response received:")
        print("   - success: \(response.success)")
        print("   - error: \(response.error ?? "none")")
        print("   - event_id: \(response.eventId?.uuidString ?? "nil")")
        print("   - most_upcoming_event_id: \(response.mostUpcomingEventId?.uuidString ?? "nil")")

        if !response.success {
            print("❌ [EventService] Event start FAILED!")
            print("   - Reason: \(response.error ?? "Unknown")")
            if let mostUpcomingId = response.mostUpcomingEventId {
                print("   - Most upcoming event ID: \(mostUpcomingId)")
            }
            throw EventServiceError.cannotStartEvent(
                reason: response.error ?? "Unknown error",
                mostUpcomingEventId: response.mostUpcomingEventId
            )
        }

        print("✅ [EventService] Event started successfully!")
        return response
    }

    /// Stops an event (sets is_active = false)
    /// - Parameter eventId: The event ID to deactivate
    /// - Returns: Result indicating success or failure
    func stopEvent(eventId: UUID) async throws -> EventActionResponse {
        let userId = try await SupabaseManager.shared.getCurrentUserId()

        let response: EventActionResponse = try await supabase
            .rpc(SupabaseConfig.Functions.stopEvent, params: StopEventParams(p_event_id: eventId.uuidString, p_user_id: userId.uuidString))
            .execute()
            .value

        if !response.success {
            throw EventServiceError.cannotStopEvent(
                reason: response.error ?? "Unknown error"
            )
        }

        return response
    }

    /// Gets the currently active event
    /// - Returns: The active event, or nil if none is active
    func getActiveEvent() async throws -> EventRecord? {
        let userId = try await SupabaseManager.shared.getCurrentUserId()

        let response: EventRecord? = try? await supabase
            .from(SupabaseConfig.Tables.events)
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .single()
            .execute()
            .value

        return response
    }

    // MARK: - Memories with Events

    /// Fetches memories with their associated event details
    /// - Returns: Array of memories with event information
    func fetchMemoriesWithEvents() async throws -> [MemoryWithEvent] {
        let userId = try await SupabaseManager.shared.getCurrentUserId()

        let response: [MemoryWithEvent] = try await supabase
            .from(SupabaseConfig.Views.memoriesWithEvents)
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("timestamp", ascending: false)
            .execute()
            .value

        return response
    }

    /// Fetches memories for a specific event
    /// - Parameter eventId: The event ID
    /// - Returns: Array of memories associated with the event
    func fetchMemories(forEvent eventId: UUID) async throws -> [MemoryWithEvent] {
        let userId = try await SupabaseManager.shared.getCurrentUserId()

        let response: [MemoryWithEvent] = try await supabase
            .from(SupabaseConfig.Views.memoriesWithEvents)
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("event_id", value: eventId.uuidString)
            .order("timestamp", ascending: false)
            .execute()
            .value

        return response
    }

    // MARK: - Utility Methods

    /// Checks if an event can be started (is it the most upcoming?)
    /// - Parameter eventId: The event ID to check
    /// - Returns: True if the event can be started, false otherwise
    func canStartEvent(eventId: UUID) async throws -> Bool {
        let mostUpcoming = try await getMostUpcomingEvent()
        guard let mostUpcoming else {
            return false
        }

        return mostUpcoming.id == eventId
    }

    /// Gets upcoming events (events that haven't ended yet)
    /// - Returns: Array of upcoming events
    func getUpcomingEvents() async throws -> [EventRecord] {
        let allEvents = try await fetchEvents()
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        return allEvents.filter { event in
            // Check if event has ended
            if let endTime = event.endTime {
                // Combine event date + end time
                let eventDay = calendar.startOfDay(for: event.eventDate)
                let endHour = calendar.component(.hour, from: endTime)
                let endMinute = calendar.component(.minute, from: endTime)

                guard let eventEndDateTime = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: eventDay) else {
                    return calendar.startOfDay(for: event.eventDate) >= today
                }

                return eventEndDateTime >= now
            } else {
                // No end time - use date-only comparison
                return calendar.startOfDay(for: event.eventDate) >= today
            }
        }
    }

    /// Gets past events (events that have already ended)
    /// - Returns: Array of past events
    func getPastEvents() async throws -> [EventRecord] {
        let allEvents = try await fetchEvents()
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        return allEvents.filter { event in
            // Check if event has ended
            if let endTime = event.endTime {
                // Combine event date + end time
                let eventDay = calendar.startOfDay(for: event.eventDate)
                let endHour = calendar.component(.hour, from: endTime)
                let endMinute = calendar.component(.minute, from: endTime)

                guard let eventEndDateTime = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: eventDay) else {
                    return calendar.startOfDay(for: event.eventDate) < today
                }

                return eventEndDateTime < now
            } else {
                // No end time - use date-only comparison
                return calendar.startOfDay(for: event.eventDate) < today
            }
        }
    }
}

// MARK: - Error Handling

enum EventServiceError: LocalizedError {
    case notAuthenticated
    case cannotStartEvent(reason: String, mostUpcomingEventId: UUID?)
    case cannotStopEvent(reason: String)
    case eventNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .cannotStartEvent(let reason, _):
            return "Cannot start event: \(reason)"
        case .cannotStopEvent(let reason):
            return "Cannot stop event: \(reason)"
        case .eventNotFound:
            return "Event not found"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue"
        case .cannotStartEvent(_, let mostUpcomingId):
            if let eventId = mostUpcomingId {
                return "You can only start the most upcoming event. Try starting event: \(eventId.uuidString)"
            }
            return "You can only start the most upcoming event"
        case .cannotStopEvent:
            return "Please try again later"
        case .eventNotFound:
            return "The event may have been deleted"
        }
    }
}
