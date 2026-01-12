//
//  MemoriesHomeView.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import SwiftUI
import SwiftData
import Auth

struct MemoriesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @State private var memoryService: MemoryService?
    @State private var showMediaTypePicker = false
    @State private var navigateToPlayback = false

    // Event management
    private let eventService = EventService()
    let selectedEvent: EventRecord? // Event passed from EventsHomeView
    let isPastEvent: Bool // Flag to indicate if this is a past event (disables Add/End actions)
    @State private var activeEvent: EventRecord?
    @State private var upcomingEvents: [EventRecord] = []
    @State private var showEventCreation = false

    init(selectedEvent: EventRecord? = nil, isPastEvent: Bool = false) {
        self.selectedEvent = selectedEvent
        self.isPastEvent = isPastEvent
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

                VStack(spacing: 40) {
                    // Active Event Badge
                    if let active = activeEvent {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "calendar.badge.checkmark")
                                    .foregroundColor(.green)
                                Text(active.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Button("Stop Event") {
                                    Task {
                                        await stopActiveEvent()
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                    }

                    Spacer()

                    // Title
                    VStack(spacing: 8) {
                        Text(activeEvent?.name ?? "Your Memories")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        if let service = memoryService {
                            Text("\(service.memories.count) memories captured")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Circular Add Memories Button (hidden for past events)
                    if !isPastEvent {
                        Button(action: {
                            showMediaTypePicker = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.blue, .purple]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 200, height: 200)
                                    .shadow(color: .blue.opacity(0.4), radius: 20, x: 0, y: 10)

                                VStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white)

                                    Text("Add Memories")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    Spacer()

                    // Play Button
                    Button(action: {
                        print("🎬 Play button tapped")
                        print("📊 Memory service: \(memoryService != nil ? "exists" : "nil")")
                        print("📊 Current user ID: \(authService.currentUserId?.uuidString ?? "nil")")
                        print("📊 Memories count: \(memoryService?.memories.count ?? 0)")
                        navigateToPlayback = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill")
                                .font(.title2)

                            Text("Play Memories")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.green, .mint]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(15)
                        .shadow(color: .green.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                    .disabled(memoryService?.memories.isEmpty ?? true)
                    .opacity((memoryService?.memories.isEmpty ?? true) ? 0.5 : 1.0)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only show toolbar buttons if NOT a past event
                if !isPastEvent {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if activeEvent != nil {
                            // Show "End Event" button when event is active
                            Button {
                                Task {
                                    await endEventAndNavigateToPlayback()
                                }
                            } label: {
                                Text("End Event")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        } else {
                            // Show schedule icon when no event is active
                            Button {
                                showEventCreation = true
                            } label: {
                                Image(systemName: "calendar.badge.plus")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showEventCreation) {
                EventManagementView(
                    activeEvent: activeEvent,
                    upcomingEvents: upcomingEvents,
                    onCreateEvent: createEvent,
                    onStartEvent: startEvent
                )
            }
            .navigationDestination(isPresented: $navigateToPlayback) {
                Group {
                    if let service = memoryService,
                       let userId = authService.currentUserId {
                        MemoryPlaybackView(
                            memoryService: service,
                            userId: userId,
                            eventName: activeEvent?.name
                        )
                        .onAppear {
                            print("✅ Navigating to playback with \(service.memories.count) memories")
                        }
                    } else {
                        Text("Error: Unable to load memories")
                            .foregroundColor(.red)
                            .onAppear {
                                print("❌ Cannot navigate - service: \(memoryService != nil), userId: \(authService.currentUserId != nil)")
                            }
                    }
                }
            }
            .sheet(isPresented: $showMediaTypePicker, onDismiss: {
                // Refresh memories when sheet is dismissed
                if let userId = authService.currentUserId {
                    memoryService?.fetchLocalMemories(userId: userId)
                }
            }) {
                if let service = memoryService,
                   let userId = authService.currentUserId {
                    MediaTypePickerView(
                        memoryService: service,
                        userId: userId,
                        eventId: activeEvent?.id,
                        eventName: activeEvent?.name
                    )
                }
            }
            .onAppear {
                setupMemoryService()
            }
        }
    }

    private func setupMemoryService() {
        if memoryService == nil {
            memoryService = MemoryService(modelContext: modelContext)
        }

        // Get the real Supabase user ID
        Task {
            do {
                let supabaseUser = try await SupabaseManager.shared.getCurrentUser()
                let realUserId = supabaseUser.id

                // Update the local user with the correct ID
                if let currentUser = authService.currentUser {
                    currentUser.id = realUserId
                }

                await MainActor.run {
                    memoryService?.fetchLocalMemories(userId: realUserId)
                }

                // Sync with remote in background
                await memoryService?.syncMemories(userId: realUserId)

                // Load events
                await loadEvents()

                // If selectedEvent was provided, use it as activeEvent
                if let selected = selectedEvent {
                    await MainActor.run {
                        activeEvent = selected
                    }
                }
            } catch {
                print("❌ Failed to get Supabase user: \(error)")
            }
        }
    }

    // MARK: - Event Management

    private func loadEvents() async {
        do {
            activeEvent = try await eventService.getActiveEvent()
            upcomingEvents = try await eventService.getUpcomingEvents()
        } catch {
            print("❌ Failed to load events: \(error)")
        }
    }

    private func createEvent(name: String, eventDate: Date, startTime: Date?, endTime: Date?) async {
        do {
            let userId = try await SupabaseManager.shared.getCurrentUserId()
            let event = Event(
                userId: userId,
                name: name,
                eventDate: eventDate,
                startTime: startTime,
                endTime: endTime
            )
            _ = try await eventService.createEvent(event)
            await loadEvents()
        } catch {
            print("❌ Failed to create event: \(error)")
        }
    }

    private func startEvent(_ event: EventRecord) async {
        do {
            _ = try await eventService.startEvent(eventId: event.id)
            await loadEvents()
        } catch {
            print("❌ Failed to start event: \(error)")
        }
    }

    private func stopActiveEvent() async {
        guard let active = activeEvent else { return }
        do {
            _ = try await eventService.stopEvent(eventId: active.id)
            await loadEvents()
        } catch {
            print("❌ Failed to stop event: \(error)")
        }
    }

    private func endEventAndNavigateToPlayback() async {
        guard let active = activeEvent else { return }

        print("🛑 [MemoriesHomeView] Ending event: \(active.name)")

        do {
            // Stop the event
            _ = try await eventService.stopEvent(eventId: active.id)
            print("✅ [MemoriesHomeView] Event stopped successfully")

            // Reload events to update state
            await loadEvents()

            // Navigate to playback
            await MainActor.run {
                print("🎬 [MemoriesHomeView] Navigating to playback screen...")
                navigateToPlayback = true
            }
        } catch {
            print("❌ [MemoriesHomeView] Failed to stop event: \(error)")
        }
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Event Management View
struct EventManagementView: View {
    @Environment(\.dismiss) private var dismiss
    let activeEvent: EventRecord?
    let upcomingEvents: [EventRecord]
    let onCreateEvent: (String, Date, Date?, Date?) async -> Void
    let onStartEvent: (EventRecord) async -> Void

    @State private var showCreateForm = false
    @State private var eventName = ""
    @State private var eventDate = Date()
    @State private var hasTimeRange = false
    @State private var startTime = Date()
    @State private var endTime = Date()

    var body: some View {
        NavigationStack {
            List {
                if let active = activeEvent {
                    Section("Active Event") {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(active.name)
                                    .font(.headline)
                                Text(active.eventDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }

                if !upcomingEvents.isEmpty {
                    Section("Upcoming Events") {
                        ForEach(upcomingEvents, id: \.id) { event in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(event.name)
                                        .font(.headline)
                                    Text(event.eventDate, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if activeEvent == nil {
                                    Button("Start") {
                                        Task {
                                            await onStartEvent(event)
                                            dismiss()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section {
                    if showCreateForm {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Event Name", text: $eventName)
                                .textFieldStyle(.roundedBorder)

                            DatePicker("Date", selection: $eventDate, displayedComponents: .date)

                            Toggle("Set Time Range", isOn: $hasTimeRange)

                            if hasTimeRange {
                                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                            }

                            HStack {
                                Button("Cancel") {
                                    showCreateForm = false
                                    eventName = ""
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button("Create") {
                                    Task {
                                        await onCreateEvent(
                                            eventName,
                                            eventDate,
                                            hasTimeRange ? startTime : nil,
                                            hasTimeRange ? endTime : nil
                                        )
                                        showCreateForm = false
                                        eventName = ""
                                        dismiss()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(eventName.isEmpty)
                            }
                        }
                    } else {
                        Button {
                            showCreateForm = true
                        } label: {
                            Label("Create New Event", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Manage Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var authService = AuthenticationService()
    return MemoriesHomeView()
        .environment(authService)
        .modelContainer(for: [Memory.self], inMemory: true)
}
