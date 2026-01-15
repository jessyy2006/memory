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
            // Schema migration failed - this happens when Memory model changed (eventId: UUID? -> UUID)
            // Solution: Delete the old database and create a fresh one
            print("⚠️ [MemoryApp] ModelContainer creation failed (likely schema mismatch)")
            print("⚠️ [MemoryApp] This is expected after making eventId non-optional")
            print("🔄 [MemoryApp] Clearing local SwiftData cache...")

            // Delete the old database files
            let fileManager = FileManager.default
            if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeURL = appSupportURL.appendingPathComponent("default.store")
                try? fileManager.removeItem(at: storeURL)
                print("✅ [MemoryApp] Cleared local database - will sync fresh from Supabase")
            }

            // Try creating container again with fresh database
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after clearing database: \(error)")
            }
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
