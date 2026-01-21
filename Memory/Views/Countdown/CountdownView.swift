//
//  CountdownView.swift
//  Memory
//
//  Created by Jessica Young on 1/20/26.
//

import SwiftUI
import SwiftData

struct CountdownView: View {
    let memoryService: MemoryService
    let userId: UUID
    let eventId: UUID
    let eventName: String?
    let onPopToRoot: (() -> Void)? // Callback to pop to EventsHomeView

    @State private var timeRemaining = 30
    @State private var navigateToPlayback = false
    @State private var timer: Timer?
    @State private var hasStarted = false // Prevent timer restart on back navigation

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

            VStack(spacing: 60) {
                Spacer()

                // Event name
                if let name = eventName {
                    Text(name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                // Countdown timer with progress ring
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                        .frame(width: 280, height: 280)

                    // Animated progress ring
                    Circle()
                        .trim(from: 0, to: CGFloat(timeRemaining) / 30.0)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round)
                        )
                        .frame(width: 280, height: 280)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timeRemaining)

                    // Countdown number
                    VStack(spacing: 8) {
                        Text("\(timeRemaining)")
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("seconds")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Skip button
                Button(action: {
                    stopTimer()
                    navigateToPlayback = true
                }) {
                    Text("Skip")
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
                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Only start countdown once - prevent restart on back navigation
            if !hasStarted {
                hasStarted = true
                startCountdown()
            }
        }
        .onDisappear {
            stopTimer()
        }
        .navigationDestination(isPresented: $navigateToPlayback) {
            MemoryPlaybackView(
                memoryService: memoryService,
                userId: userId,
                eventId: eventId,
                eventName: eventName,
                onPopToRoot: onPopToRoot
            )
        }
    }

    private func startCountdown() {
        print("⏰ [CountdownView] Starting 30-second countdown")
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                stopTimer()
                print("⏰ [CountdownView] Countdown complete - auto-navigating to playback")
                navigateToPlayback = true
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    @Previewable @State var modelContext = try! ModelContainer(
        for: Memory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ).mainContext

    return NavigationStack {
        CountdownView(
            memoryService: MemoryService(modelContext: modelContext),
            userId: UUID(),
            eventId: UUID(),
            eventName: "Test Event",
            onPopToRoot: nil
        )
    }
}
