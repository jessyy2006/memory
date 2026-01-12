//
//  EventsTestView.swift
//  Memory
//
//  Created by Jessica Young on 1/11/26.
//

import SwiftUI

struct EventsTestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @State private var events: [EventRecord] = []
    @State private var activeEvent: EventRecord?
    @State private var errorMessage: String?
    @State private var showingCreateEvent = false
    @State private var hasValidSession = false
    @State private var isCheckingSession = true

    private let eventService = EventService()

    var body: some View {
        NavigationView {
            Group {
                if isCheckingSession {
                    ProgressView("Checking session...")
                } else if !hasValidSession {
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.red)

                        Text("Session Expired")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Your Supabase session has expired. Please sign out and sign back in.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        Button("Sign Out") {
                            Task {
                                await authService.signOut()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Go Back") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    VStack {
                        // Active Event Section
                        if let active = activeEvent {
                            ActiveEventCard(event: active, onStop: stopActiveEvent)
                                .padding()
                        }

                        // Events List
                        List {
                            Section("Upcoming Events") {
                                ForEach(upcomingEvents, id: \.id) { event in
                                    EventRowTest(
                                        event: event,
                                        onStart: { await startEvent(event) },
                                        onDelete: { await deleteEvent(event) }
                                    )
                                }
                            }

                            Section("Past Events") {
                                ForEach(pastEvents, id: \.id) { event in
                                    EventRowTest(
                                        event: event,
                                        onStart: nil,
                                        onDelete: { await deleteEvent(event) }
                                    )
                                }
                            }
                        }

                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .padding()
                        }
                    }
                    .navigationTitle("Events Test")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Create Event") {
                                showingCreateEvent = true
                            }
                        }

                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Refresh") {
                                Task {
                                    await loadEvents()
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showingCreateEvent) {
                        CreateEventView(onCreate: { event in
                            await createEvent(event)
                        })
                    }
                }
            }
            .task {
                await checkSession()
                if hasValidSession {
                    await loadEvents()
                }
            }
        }
    }

    // MARK: - Computed Properties

    var upcomingEvents: [EventRecord] {
        events.filter { $0.isUpcoming == true }
    }

    var pastEvents: [EventRecord] {
        events.filter { $0.isUpcoming == false }
    }

    // MARK: - Functions

    func checkSession() async {
        isCheckingSession = true
        do {
            _ = try await SupabaseManager.shared.getCurrentUser()
            hasValidSession = true
        } catch {
            hasValidSession = false
            print("Session check failed: \(error)")
        }
        isCheckingSession = false
    }

    func loadEvents() async {
        do {
            events = try await eventService.fetchEvents()
            activeEvent = try await eventService.getActiveEvent()
            errorMessage = nil
        } catch {
            let errorDesc = error.localizedDescription
            if errorDesc.contains("session") || errorDesc.contains("Session") {
                errorMessage = "Please sign in to view events. Session may have expired."
            } else {
                errorMessage = "Failed to load events: \(errorDesc)"
            }
            print("Error loading events: \(error)")
        }
    }

    func createEvent(_ event: Event) async {
        do {
            _ = try await eventService.createEvent(event)
            await loadEvents()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to create event: \(error.localizedDescription)"
            print("Error creating event: \(error)")
        }
    }

    func startEvent(_ event: EventRecord) async {
        do {
            _ = try await eventService.startEvent(eventId: event.id)
            await loadEvents()
            errorMessage = nil
        } catch EventServiceError.cannotStartEvent(let reason, let suggestedId) {
            errorMessage = "Cannot start event: \(reason)"
            if let id = suggestedId {
                errorMessage! += "\nTry starting event: \(id)"
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }

    func stopActiveEvent() async {
        guard let active = activeEvent else { return }

        do {
            _ = try await eventService.stopEvent(eventId: active.id)
            await loadEvents()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to stop event: \(error.localizedDescription)"
        }
    }

    func deleteEvent(_ event: EventRecord) async {
        do {
            try await eventService.deleteEvent(id: event.id)
            await loadEvents()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to delete event: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Views

struct ActiveEventCard: View {
    let event: EventRecord
    let onStop: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundColor(.red)
                    .imageScale(.large)

                VStack(alignment: .leading) {
                    Text("Active Event")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.name)
                        .font(.headline)
                }

                Spacer()

                Button("Stop") {
                    Task {
                        await onStop()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

struct EventRowTest: View {
    let event: EventRecord
    let onStart: (() async -> Void)?
    let onDelete: () async -> Void

    @State private var canStart = false
    private let eventService = EventService()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.name)
                    .font(.headline)

                HStack {
                    Image(systemName: "calendar")
                        .imageScale(.small)
                    Text(event.eventDate, style: .date)
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                if let start = event.startTime, let end = event.endTime {
                    HStack {
                        Image(systemName: "clock")
                            .imageScale(.small)
                        Text("\(start, style: .time) - \(end, style: .time)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            if event.isActive {
                Text("Active")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            } else if let startAction = onStart, canStart {
                Button("Start") {
                    Task {
                        await startAction()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task {
                    await onDelete()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            if onStart != nil {
                canStart = (try? await eventService.canStartEvent(eventId: event.id)) ?? false
            }
        }
    }
}

struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var eventDate = Date()
    @State private var hasTimeRange = false
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var isCreating = false
    @State private var errorMessage: String?

    let onCreate: (Event) async -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Event Name", text: $name)
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                }

                Section {
                    Toggle("Set Time Range", isOn: $hasTimeRange)

                    if hasTimeRange {
                        DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(isCreating ? "Creating..." : "Create Event") {
                        Task {
                            await createEvent()
                        }
                    }
                    .disabled(name.isEmpty || isCreating)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    func createEvent() async {
        isCreating = true
        errorMessage = nil

        do {
            let userId = try await SupabaseManager.shared.getCurrentUserId()

            let event = Event(
                userId: userId,
                name: name,
                eventDate: eventDate,
                startTime: hasTimeRange ? startTime : nil,
                endTime: hasTimeRange ? endTime : nil
            )

            await onCreate(event)
            dismiss()
        } catch {
            errorMessage = "Failed to create event: \(error.localizedDescription)"
            isCreating = false
        }
    }
}

#Preview {
    @Previewable @State var authService = AuthenticationService()
    return EventsTestView()
        .environment(authService)
}
