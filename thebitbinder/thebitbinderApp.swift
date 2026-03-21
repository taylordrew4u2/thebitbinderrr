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
    @StateObject private var startup = AppStartupCoordinator()
    @StateObject private var userPreferences = UserPreferences()
    
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
            ImportBatch.self,
            ImportedJokeMetadata.self,
            UnresolvedImportFragment.self,
            ChatMessage.self,
        ])

        // One store file. All fallbacks use this same URL — never switch to a
        // different file, which would silently lose all user data.
        // IMPORTANT: SwiftData's default store name is "default.store".
        // Changing this to anything else creates a NEW empty store and makes
        // all existing user data invisible. Always use "default.store".
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        
        // 🛡️ CRITICAL DATA PROTECTION: Check if store file exists and create emergency backup
        if FileManager.default.fileExists(atPath: storeURL.path) {
            let emergencyBackupURL = URL.applicationSupportDirectory
                .appending(path: "emergency_backup_\(Int(Date().timeIntervalSince1970)).store")
            
            do {
                try FileManager.default.copyItem(at: storeURL, to: emergencyBackupURL)
                print("🛡️ [DataProtection] Emergency backup created before container initialization")
            } catch {
                print("⚠️ [DataProtection] Could not create emergency backup: \(error)")
            }
        }

        // 1️⃣ Persistent + CloudKit (single container, full schema)
        do {
            let config = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .private("iCloud.666bit")
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            print("✅ [ModelContainer] Persistent + CloudKit ready")
            
            // Log successful container creation
            DataOperationLogger.shared.logCritical("ModelContainer created successfully with CloudKit")
            
            return container
        } catch {
            print("⚠️ [ModelContainer] CloudKit failed (\(error)) — local-only fallback (same file, data preserved)")
            DataOperationLogger.shared.logError(error, operation: "ModelContainer_CloudKit_Creation")
        }

        // 2️⃣ Same file, no CloudKit — all data preserved, just no sync
        do {
            let config = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            print("✅ [ModelContainer] Persistent local-only ready")
            
            DataOperationLogger.shared.logCritical("ModelContainer created successfully (local-only fallback)")
            
            return container
        } catch {
            print("❌ [ModelContainer] Local store failed (\(error)) — attempting data preservation backup")
            DataOperationLogger.shared.logError(error, operation: "ModelContainer_Local_Creation")
            
            // 🛡️ CRITICAL: Back up corrupted store with more detail before wiping
            let timestamp = Int(Date().timeIntervalSince1970)
            let backupURL = URL.applicationSupportDirectory
                .appending(path: "corrupted_store_backup_\(timestamp).store")
            
            do {
                try FileManager.default.copyItem(at: storeURL, to: backupURL)
                print("✅ [ModelContainer] Corrupted store backed up to: \(backupURL.lastPathComponent)")
                DataOperationLogger.shared.logCritical("Corrupted store backed up before cleanup")
            } catch {
                print("❌ [ModelContainer] Could not backup corrupted store: \(error)")
                DataOperationLogger.shared.logError(error, operation: "Corrupted_Store_Backup")
            }
        }

        // 3️⃣ Last resort: wipe corrupted files at same URL (backup already saved above)
        print("🔧 [ModelContainer] Cleaning corrupted store files...")
        DataOperationLogger.shared.logCritical("Cleaning corrupted store files as last resort")
        
        for ext in ["", "-shm", "-wal"] {
            let fileURL = URL.applicationSupportDirectory.appending(path: "default.store\(ext)")
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("   Removed: default.store\(ext)")
                }
            } catch {
                print("   Failed to remove default.store\(ext): \(error)")
            }
        }
        
        do {
            let config = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            print("⚠️ [ModelContainer] Fresh store at same URL (corrupted store was backed up)")
            
            DataOperationLogger.shared.logCritical("Fresh store created after corruption cleanup - data may be lost but backups available")
            
            return container
        } catch {
            // 🚨 CATASTROPHIC FAILURE - Log everything possible
            print("❌ [ModelContainer] CATASTROPHIC FAILURE: Cannot create any persistent store: \(error)")
            DataOperationLogger.shared.logCritical("CATASTROPHIC FAILURE: Cannot create ModelContainer - \(error.localizedDescription)")
            
            // Try to create in-memory as absolute last resort to prevent app crash
            do {
                let config = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                let container = try ModelContainer(for: schema, configurations: [config])
                print("🆘 [ModelContainer] EMERGENCY: Created in-memory container - DATA WILL BE LOST ON APP CLOSE")
                DataOperationLogger.shared.logCritical("EMERGENCY: Created in-memory container - all data will be lost")
                
                return container
            } catch {
                DataOperationLogger.shared.logCritical("TOTAL FAILURE: Cannot create any ModelContainer - app will crash")
                fatalError("❌ [ModelContainer] TOTAL FAILURE: Cannot create any ModelContainer: \(error)")
            }
        }
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if startup.isReady {
                    ContentView()
                } else {
                    LaunchScreenView(statusText: startup.statusText, userName: userPreferences.userName)
                }
            }
            .task {
                // Wire the main context into the sync service so remote change
                // notifications can call refreshAllObjects() on the right context
                iCloudSyncService.shared.modelContext = sharedModelContainer.mainContext
                
                // Register for remote push notifications — CloudKit uses silent
                // pushes to tell the app "new data available, please fetch"
                // Without this, sync only happens when the app is foregrounded
                UIApplication.shared.registerForRemoteNotifications()
                
                #if DEBUG
                // CloudKit debugging for development
                CloudKitResetUtility.logContainerInfo()
                #endif
                
                // Start app initialization
                await startup.start()
                
                // Complete data protection with model context
                await startup.completeDataProtectionWithContext(sharedModelContainer.mainContext)
            }
            .environmentObject(userPreferences)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                try? sharedModelContainer.mainContext.save()
                iCloudKeyValueStore.shared.pushToCloud()
            } else if scenePhase == .active {
                // Save triggers SwiftData to merge any pending remote changes into the UI
                try? sharedModelContainer.mainContext.save()
                iCloudKeyValueStore.shared.pullFromCloud()
                NotificationManager.shared.scheduleIfNeeded()
            }
        }
    }
}
