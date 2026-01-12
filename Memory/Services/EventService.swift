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
        let insert = EventInsert(event: event)

        let response: EventRecord = try await supabase
            .from(SupabaseConfig.Tables.events)
            .insert(insert)
            .select()
            .single()
            .execute()
            .value

        return response
    }

    /// Fetches all events for the current user, sorted by event_date
    /// - Returns: Array of event records sorted by date
    func fetchEvents() async throws -> [EventRecord] {
        let userId = try await SupabaseManager.shared.getCurrentUserId()

        // Use the stored procedure for sorted events
        let response: [EventRecord] = try await supabase
            .rpc(SupabaseConfig.Functions.getEventsSorted, params: GetEventsSortedParams(p_user_id: userId.uuidString))
            .execute()
            .value

        return response
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

        let response: EventActionResponse = try await supabase
            .rpc(SupabaseConfig.Functions.startEvent, params: StartEventParams(p_event_id: eventId.uuidString, p_user_id: userId.uuidString))
            .execute()
            .value

        if !response.success {
            throw EventServiceError.cannotStartEvent(
                reason: response.error ?? "Unknown error",
                mostUpcomingEventId: response.mostUpcomingEventId
            )
        }

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

    /// Gets upcoming events (event_date >= current date)
    /// - Returns: Array of upcoming events
    func getUpcomingEvents() async throws -> [EventRecord] {
        let allEvents = try await fetchEvents()
        return allEvents.filter { $0.isUpcoming == true }
    }

    /// Gets past events (event_date < current date)
    /// - Returns: Array of past events
    func getPastEvents() async throws -> [EventRecord] {
        let allEvents = try await fetchEvents()
        return allEvents.filter { $0.isUpcoming == false }
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
