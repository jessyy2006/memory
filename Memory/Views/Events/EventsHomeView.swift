//
//  EventsHomeView.swift
//  Memory
//
//  Created by Jessica Young on 1/12/26.
//

import SwiftUI

struct EventsHomeView: View {
    @Environment(AuthenticationService.self) private var authService
    private let eventService = EventService()

    @State private var allEvents: [EventRecord] = []
    @State private var activeEvent: EventRecord?
    @State private var isLoading = false
    @State private var showCreateEvent = false
    @State private var errorMessage: String?

    // Confirmation dialog state
    @State private var eventToStart: EventRecord?
    @State private var showStartConfirmation = false

    // Error alert states
    @State private var showMultipleEventsAlert = false
    @State private var showNotUpcomingAlert = false

    // Navigation
    @State private var navigateToMemories: EventRecord?
    @State private var navigateToPastEvents = false

    // Filtered events for display
    private var activeEvents: [EventRecord] {
        allEvents.filter { !$0.isEnded }
    }

    private var pastEvents: [EventRecord] {
        allEvents.filter { $0.isEnded }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.systemGray6)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLoading {
                        Spacer()
                        ProgressView("Loading events...")
                        Spacer()
                    } else if activeEvents.isEmpty && pastEvents.isEmpty {
                        // Empty State
                        VStack(spacing: 24) {
                            Spacer()

                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 80))
                                .foregroundColor(.blue.opacity(0.5))

                            Text("No Events Yet")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Create your first event to start\ncapturing memories")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Button {
                                showCreateEvent = true
                            } label: {
                                Label("Create Event", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.blue, .purple]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(15)
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 16)

                            Spacer()
                        }
                    } else {
                        // Events List
                        ScrollView {
                            VStack(spacing: 16) {
                                // Header
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("My Events")
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                        Text("\(activeEvents.count) event\(activeEvents.count == 1 ? "" : "s")")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 20)

                                // Events Cards (only non-ended events)
                                ForEach(activeEvents, id: \.id) { event in
                                    EventCard(
                                        event: event,
                                        isActive: event.id == activeEvent?.id,
                                        onTap: {
                                            handleEventTap(event)
                                        }
                                    )
                                    .padding(.horizontal, 20)
                                }

                                // Add some bottom padding
                                Color.clear.frame(height: 80)
                            }
                        }
                    }
                }

                // Past Events Button (fixed to bottom with 32px padding)
                if !pastEvents.isEmpty {
                    VStack {
                        Spacer()
                        Button {
                            navigateToPastEvents = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Past Events")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text("\(pastEvents.count) ended event\(pastEvents.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only show + button when there are events
                if !allEvents.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showCreateEvent = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task {
                            await authService.signOut()
                        }
                    } label: {
                        Image(systemName: "arrow.left.circle")
                    }
                }
            }
            .sheet(isPresented: $showCreateEvent) {
                CreateEventFormView { name, date, startTime, endTime in
                    await createEvent(name: name, eventDate: date, startTime: startTime, endTime: endTime)
                }
            }
            .navigationDestination(item: $navigateToMemories) { event in
                MemoriesHomeView(selectedEvent: event)
            }
            .navigationDestination(isPresented: $navigateToPastEvents) {
                PastEventsView()
            }
            .alert("Start Event", isPresented: $showStartConfirmation) {
                Button("Cancel", role: .cancel) {
                    eventToStart = nil
                }
                Button("Start") {
                    if let event = eventToStart {
                        Task {
                            await startEvent(event)
                        }
                    }
                }
            } message: {
                if let event = eventToStart {
                    Text("Do you want to start '\(event.name)'?")
                }
            }
            .alert("Can't Start Multiple Events", isPresented: $showMultipleEventsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Can't start multiple events at the same time.")
            }
            .alert("Patience!", isPresented: $showNotUpcomingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You have other events to go to first")
            }
            .onAppear {
                print("👁️ [EventsHomeView] View appeared!")
                print("👁️ [EventsHomeView] Current user ID: \(authService.currentUserId?.uuidString ?? "nil")")
                print("👁️ [EventsHomeView] Is authenticated: \(authService.isAuthenticated)")
                Task {
                    await loadEvents()
                }
            }
            .onChange(of: navigateToMemories) { oldValue, newValue in
                // Reload events when coming back from MemoriesHomeView
                if oldValue != nil && newValue == nil {
                    print("🔄 [EventsHomeView] Returned from MemoriesHomeView, reloading events...")
                    Task {
                        await loadEvents()
                    }
                }
            }
        }
    }

    // MARK: - Event Handling

    private func handleEventTap(_ event: EventRecord) {
        if event.id == activeEvent?.id {
            // Already active - navigate to memories
            navigateToMemories = event
        } else if event.isActive {
            // Some other event is active, but this one isn't - shouldn't happen
            // Just navigate to memories anyway
            navigateToMemories = event
        } else {
            // Inactive event - validate before showing confirmation

            // Check 1: Is there already an active event?
            if activeEvent != nil {
                showMultipleEventsAlert = true
                return
            }

            // Check 2: Is this event NOT the most upcoming one?
            if event.isUpcoming == false {
                showNotUpcomingAlert = true
                return
            }

            // All validations passed - show confirmation
            eventToStart = event
            showStartConfirmation = true
        }
    }

    private func loadEvents() async {
        await MainActor.run {
            isLoading = true
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            print("🔄 [EventsHomeView] Starting loadEvents()...")

            // Check if user is authenticated
            guard let userId = authService.currentUserId else {
                print("❌ [EventsHomeView] No user ID found - user not authenticated")
                await MainActor.run {
                    errorMessage = "Not authenticated"
                }
                return
            }

            print("✅ [EventsHomeView] User authenticated: \(userId)")

            // Fetch ALL events (no filtering by is_active)
            let fetchedEvents = try await eventService.fetchEvents()
            print("📥 [EventsHomeView] Received \(fetchedEvents.count) events from EventService")

            // Get the active event separately
            let fetchedActiveEvent = try await eventService.getActiveEvent()
            print("📥 [EventsHomeView] Active event: \(fetchedActiveEvent?.name ?? "none")")

            // Update UI on main thread
            await MainActor.run {
                allEvents = fetchedEvents
                activeEvent = fetchedActiveEvent

                print("✅ [EventsHomeView] UI Updated - Displaying \(allEvents.count) events")
                if let active = activeEvent {
                    print("   ✓ Active event: \(active.name) (ID: \(active.id))")
                }

                // Debug: Print each event with full details
                print("📋 [EventsHomeView] Event List:")
                for (index, event) in allEvents.enumerated() {
                    print("   \(index + 1). \(event.name)")
                    print("      - ID: \(event.id)")
                    print("      - Date: \(event.eventDate)")
                    print("      - is_active: \(event.isActive)")
                    print("      - is_upcoming: \(event.isUpcoming ?? false)")
                }

                if allEvents.isEmpty {
                    print("⚠️ [EventsHomeView] No events to display - showing empty state")
                }
            }
        } catch {
            print("❌ [EventsHomeView] Failed to load events: \(error)")
            print("❌ [EventsHomeView] Error details: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Failed to load events: \(error.localizedDescription)"
            }
        }
    }

    private func createEvent(name: String, eventDate: Date, startTime: Date?, endTime: Date?) async {
        do {
            print("📝 [EventsHomeView] Creating event: \(name)")
            let userId = try await SupabaseManager.shared.getCurrentUserId()
            print("👤 [EventsHomeView] User ID: \(userId)")

            let event = Event(
                userId: userId,
                name: name,
                eventDate: eventDate,
                startTime: startTime,
                endTime: endTime
            )

            print("📝 [EventsHomeView] Event object created, calling EventService...")
            let createdEvent = try await eventService.createEvent(event)
            print("✅ [EventsHomeView] Event created successfully!")
            print("   - Name: \(createdEvent.name)")
            print("   - ID: \(createdEvent.id)")
            print("   - Date: \(createdEvent.eventDate)")
            print("   - is_active: \(createdEvent.isActive)")

            // Small delay to ensure Supabase has processed the insert
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Reload events after creation
            print("🔄 [EventsHomeView] Reloading events list...")
            await loadEvents()
            print("✅ [EventsHomeView] Event creation flow complete")
        } catch {
            print("❌ [EventsHomeView] Failed to create event: \(error)")
            print("❌ [EventsHomeView] Error type: \(type(of: error))")
            print("❌ [EventsHomeView] Error details: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Failed to create event: \(error.localizedDescription)"
            }
        }
    }

    private func startEvent(_ event: EventRecord) async {
        print("🎬 [EventsHomeView] Starting event: \(event.name)")
        print("   - Event ID: \(event.id)")
        print("   - Event Date: \(event.eventDate)")
        print("   - Is Upcoming: \(event.isUpcoming ?? false)")

        do {
            print("📞 [EventsHomeView] Calling EventService.startEvent()...")
            let response = try await eventService.startEvent(eventId: event.id)
            print("✅ [EventsHomeView] Event started successfully!")
            print("   - Response: \(response)")

            print("🔄 [EventsHomeView] Reloading events after start...")
            await loadEvents()

            // Navigate to memories page after successful start
            print("🧭 [EventsHomeView] Navigating to MemoriesHomeView...")
            await MainActor.run {
                navigateToMemories = event
            }
            print("✅ [EventsHomeView] Navigation triggered")
        } catch {
            print("❌ [EventsHomeView] Failed to start event: \(error)")
            print("❌ [EventsHomeView] Error type: \(type(of: error))")
            print("❌ [EventsHomeView] Error details: \(error.localizedDescription)")

            await MainActor.run {
                errorMessage = "Failed to start event: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Event Card
struct EventCard: View {
    let event: EventRecord
    let isActive: Bool
    let onTap: () -> Void

    private var isUpcoming: Bool {
        // Use the database's isUpcoming value which factors in end_time
        // Fallback to date comparison if not available
        event.isUpcoming ?? (event.eventDate >= Date())
    }

    private var isPast: Bool {
        !isUpcoming
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.caption)
                            Text(event.eventDate, style: .date)
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)

                        if let startTime = event.startTime, let endTime = event.endTime {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text("\(startTime, style: .time) - \(endTime, style: .time)")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(spacing: 8) {
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("Active")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        } else if isUpcoming {
                            Image(systemName: "clock.badge")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text("Upcoming")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Text("Ended")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                        }
                    }
                }

                if !isActive {
                    Text(isUpcoming ? "Tap to start this event" : "Tap to view memories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(isActive ? Color.green.opacity(0.1) : Color(.systemBackground))
                    .shadow(color: isActive ? .green.opacity(0.3) : .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isActive ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Create Event Form View
struct CreateEventFormView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, Date, Date?, Date?) async -> Void

    @State private var eventName = ""
    @State private var eventDate = Date()
    @State private var hasTimeRange = false
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event Name", text: $eventName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Event Details")
                }

                Section {
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)

                    Toggle("Set Time Range", isOn: $hasTimeRange)

                    if hasTimeRange {
                        DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Schedule")
                }
            }
            .navigationTitle("Create Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            isCreating = true
                            await onCreate(eventName, eventDate, hasTimeRange ? startTime : nil, hasTimeRange ? endTime : nil)
                            isCreating = false
                            dismiss()
                        }
                    }
                    .disabled(eventName.isEmpty || isCreating)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var authService = AuthenticationService()
    EventsHomeView()
        .environment(authService)
}
