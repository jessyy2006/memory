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
            if authService.isAuthenticated {
                MemoriesHomeView()
                    .environment(authService)
            } else {
                CreateAccountView()
                    .environment(authService)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
