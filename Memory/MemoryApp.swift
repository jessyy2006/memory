//
//  MemoryApp.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import SwiftUI
import SwiftData

@main
struct MemoryApp: App {
    @State private var authService = AuthenticationService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            User.self,
            Memory.self,
            Event.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if authService.isCheckingSession {
                // Show loading screen while checking for existing session
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .onAppear {
                    print("⏳ [MemoryApp] Checking for existing session...")
                }
            } else if authService.isAuthenticated {
                EventsHomeView()
                    .environment(authService)
                    .onAppear {
                        print("🏠 [MemoryApp] EventsHomeView appeared - user is authenticated")
                    }
            } else {
                CreateAccountView()
                    .environment(authService)
                    .onAppear {
                        print("📝 [MemoryApp] CreateAccountView appeared - user not authenticated")
                    }
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: authService.isAuthenticated) { oldValue, newValue in
            print("🔐 [MemoryApp] Authentication changed: \(oldValue) → \(newValue)")
        }
    }
}
