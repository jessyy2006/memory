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
                    Spacer()

                    // Title
                    VStack(spacing: 8) {
                        Text("Your Memories")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        if let service = memoryService {
                            Text("\(service.memories.count) memories captured")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Circular Add Memories Button
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
            .navigationDestination(isPresented: $navigateToPlayback) {
                Group {
                    if let service = memoryService,
                       let userId = authService.currentUserId {
                        MemoryPlaybackView(
                            memoryService: service,
                            userId: userId
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
                        userId: userId
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
            } catch {
                print("❌ Failed to get Supabase user: \(error)")
            }
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

#Preview {
    @Previewable @State var authService = AuthenticationService()
    return MemoriesHomeView()
        .environment(authService)
        .modelContainer(for: [Memory.self], inMemory: true)
}
