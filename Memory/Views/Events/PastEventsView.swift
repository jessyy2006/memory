//
//  PastEventsView.swift
//  Memory
//
//  Created by Claude on 1/12/26.
//

import SwiftUI

struct PastEventsView: View {
    @Environment(AuthenticationService.self) private var authService
    private let eventService = EventService()

    @State private var pastEvents: [EventRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Navigation
    @State private var navigateToMemories: EventRecord?

    var body: some View {
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
                    ProgressView("Loading past events...")
                    Spacer()
                } else if pastEvents.isEmpty {
                    // Empty State
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 80))
                            .foregroundColor(.gray.opacity(0.5))

                        Text("No Past Events")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Events that have ended will\nappear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Spacer()
                    }
                } else {
                    // Past Events List
                    ScrollView {
                        VStack(spacing: 16) {
                            // Header
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Past Events")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                    Text("\(pastEvents.count) ended event\(pastEvents.count == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                            // Past Events Cards
                            ForEach(pastEvents, id: \.id) { event in
                                PastEventCard(
                                    event: event,
                                    onTap: {
                                        navigateToMemories = event
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
        }
        .navigationTitle("Past Events")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $navigateToMemories) { event in
            MemoriesHomeView(selectedEvent: event)
        }
        .onAppear {
            Task {
                await loadPastEvents()
            }
        }
    }

    private func loadPastEvents() async {
        await MainActor.run {
            isLoading = true
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            print("🔄 [PastEventsView] Loading past events...")

            // Fetch past events using EventService
            let events = try await eventService.getPastEvents()
            print("📥 [PastEventsView] Received \(events.count) past events")

            // Sort by date descending (most recent first)
            let sortedEvents = events.sorted { $0.eventDate > $1.eventDate }

            await MainActor.run {
                pastEvents = sortedEvents
                print("✅ [PastEventsView] Displaying \(pastEvents.count) past events")
            }
        } catch {
            print("❌ [PastEventsView] Failed to load past events: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load past events: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Past Event Card
struct PastEventCard: View {
    let event: EventRecord
    let onTap: () -> Void

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
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Ended")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                    }
                }

                Text("Tap to view memories")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    @Previewable @State var authService = AuthenticationService()
    NavigationStack {
        PastEventsView()
            .environment(authService)
    }
}
