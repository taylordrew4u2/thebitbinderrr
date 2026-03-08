//
//  thebitbinderApp.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

@main
struct thebitbinderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Joke.self,
            JokeFolder.self,
            Recording.self,
            SetList.self,
            NotebookPhotoRecord.self,
            RoastTarget.self,
            RoastJoke.self,
            BrainstormIdea.self,
        ])

        // Primary: persistent store with CloudKit sync
        do {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .automatic
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("⚠️ [ModelContainer] Persistent store failed: \(error)")
        }

        // Fallback: persistent store without CloudKit (if container not configured in portal)
        do {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("⚠️ [ModelContainer] Non-CloudKit store also failed: \(error)")
        }

        // Last resort: in-memory (app works but data won't persist across launches)
        do {
            print("❌ [ModelContainer] Falling back to in-memory store.")
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer at all: \(error)")
        }
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Save any pending model context changes immediately
                try? sharedModelContainer.mainContext.save()
            case .active:
                // Nothing needed — SwiftData context is already live
                break
            default:
                break
            }
        }
    }
}
