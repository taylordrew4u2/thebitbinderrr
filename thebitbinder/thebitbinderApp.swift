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
            NotebookFolder.self,
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
        
        //  NOTE: Emergency backups are now performed AFTER launch in
        // performDeferredBackup() to avoid watchdog timeout (code 9).
        // The ModelContainer closure must be fast.

        // 1⃣ Persistent + CloudKit (single container, full schema)
        do {
            // CRITICAL: For CloudKit sync to work properly, we need:
            // 1. groupAppContainerIdentifier for shared access (if using app groups)
            // 2. Proper cloudKitDatabase configuration
            // The ModelConfiguration initializer automatically enables persistent history tracking
            // when cloudKitDatabase is set, which is required for sync.
            let config = ModelConfiguration(
                "BitBinderStore",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .private("iCloud.The-BitBinder.thebitbinder")
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            print(" [ModelContainer] Persistent + CloudKit ready with history tracking")
            
            // Log successful container creation
            DataOperationLogger.shared.logSuccess("ModelContainer created with CloudKit")
            
            // Verify CloudKit container identifier matches entitlements
            let cloudKitContainerID = "iCloud.The-BitBinder.thebitbinder"
            print(" [CloudKit] Using container ID: \(cloudKitContainerID)")
            
            return container
        } catch {
            print(" [ModelContainer] CloudKit failed (\(error)) — local-only fallback (same file, data preserved)")
            DataOperationLogger.shared.logError(error, operation: "ModelContainer_CloudKit_Creation")
            
            // Log the specific error for debugging
            if let nsError = error as NSError? {
                print(" [CloudKit] Error domain: \(nsError.domain)")
                print(" [CloudKit] Error code: \(nsError.code)")
                print(" [CloudKit] Error userInfo: \(nsError.userInfo)")
            }
        }

        // 2⃣ Same file, no CloudKit — all data preserved, just no sync
        do {
            let config = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            print(" [ModelContainer] Persistent local-only ready")
            
            DataOperationLogger.shared.logSuccess("ModelContainer created (local-only fallback)")
            
            return container
        } catch {
            print(" [ModelContainer] Local store failed (\(error)) — attempting data preservation backup")
            DataOperationLogger.shared.logError(error, operation: "ModelContainer_Local_Creation")
            
            //  CRITICAL: Back up ALL corrupted store components before wiping.
            // This includes -shm, -wal journal files and the _Files external
            // storage directory (@Attribute(.externalStorage) blobs like photos).
            let timestamp = Int(Date().timeIntervalSince1970)
            let backupDir = URL.applicationSupportDirectory
                .appending(path: "corrupted_store_backup_\(timestamp)", directoryHint: .isDirectory)
            
            do {
                try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
                var backedUpComponents = 0
                
                for ext in ["", "-shm", "-wal"] {
                    let src = URL(fileURLWithPath: storeURL.path + ext)
                    if FileManager.default.fileExists(atPath: src.path) {
                        let dst = backupDir.appending(path: "default.store\(ext)")
                        try FileManager.default.copyItem(at: src, to: dst)
                        backedUpComponents += 1
                        print(" [ModelContainer] Backed up: default.store\(ext)")
                    }
                }
                
                // Back up external storage directory (RoastTarget photos, etc.)
                let externalStorageURL = URL(fileURLWithPath: storeURL.path + "_Files")
                if FileManager.default.fileExists(atPath: externalStorageURL.path) {
                    let dst = backupDir.appending(path: "default.store_Files")
                    try FileManager.default.copyItem(at: externalStorageURL, to: dst)
                    backedUpComponents += 1
                    print(" [ModelContainer] Backed up: default.store_Files (external storage)")
                }
                
                print(" [ModelContainer] Corrupted store backed up (\(backedUpComponents) components) to: \(backupDir.lastPathComponent)")
                DataOperationLogger.shared.logCritical("Corrupted store backed up before cleanup (\(backedUpComponents) components)")
            } catch {
                print(" [ModelContainer] Could not backup corrupted store: \(error)")
                DataOperationLogger.shared.logError(error, operation: "Corrupted_Store_Backup")
            }
        }

        // 3⃣ Last resort: wipe corrupted files at same URL (backup already saved above)
        print(" [ModelContainer] Cleaning corrupted store files...")
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
        
        // Also clean up the external storage directory — a fresh store
        // cannot reference blobs from the corrupted store, so leaving them
        // creates orphaned files. They were already backed up above.
        let externalStorageURL = URL(fileURLWithPath: storeURL.path + "_Files")
        if FileManager.default.fileExists(atPath: externalStorageURL.path) {
            do {
                try FileManager.default.removeItem(at: externalStorageURL)
                print("   Removed: default.store_Files (external storage)")
            } catch {
                print("   Failed to remove default.store_Files: \(error)")
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
            print(" [ModelContainer] Fresh store at same URL (corrupted store was backed up)")
            
            DataOperationLogger.shared.logCritical("Fresh store created after corruption cleanup - data may be lost but backups available")
            
            // Set flag so the startup coordinator can inform the user on next launch
            UserDefaults.standard.set(true, forKey: "ModelContainer_CorruptionCleanupPerformed")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ModelContainer_CorruptionCleanupTimestamp")
            
            return container
        } catch {
            //  CATASTROPHIC FAILURE - Log everything possible
            print(" [ModelContainer] CATASTROPHIC FAILURE: Cannot create any persistent store: \(error)")
            DataOperationLogger.shared.logCritical("CATASTROPHIC FAILURE: Cannot create ModelContainer - \(error.localizedDescription)")
            
            // Try to create in-memory as absolute last resort to prevent app crash
            do {
                let config = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                let container = try ModelContainer(for: schema, configurations: [config])
                print(" [ModelContainer] EMERGENCY: Created in-memory container - DATA WILL BE LOST ON APP CLOSE")
                DataOperationLogger.shared.logCritical("EMERGENCY: Created in-memory container - all data will be lost")
                
                // Flag so user sees a warning even in the in-memory scenario
                UserDefaults.standard.set(true, forKey: "ModelContainer_CorruptionCleanupPerformed")
                UserDefaults.standard.set(true, forKey: "ModelContainer_InMemoryFallback")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ModelContainer_CorruptionCleanupTimestamp")
                
                return container
            } catch {
                DataOperationLogger.shared.logCritical("TOTAL FAILURE: Cannot create any ModelContainer - app will crash")
                fatalError(" [ModelContainer] TOTAL FAILURE: Cannot create any ModelContainer: \(error)")
            }
        }
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if startup.isReady {
                    ContentView()
                        .transition(.opacity)
                } else {
                    LaunchScreenView(statusText: startup.statusText, userName: userPreferences.userName)
                }
            }
            .animation(.easeOut(duration: 0.35), value: startup.isReady)
            .task {
                // Wire the main context into the sync service so remote change
                // notifications can call refreshAllObjects() on the right context
                iCloudSyncService.shared.modelContext = sharedModelContainer.mainContext
                
                // Register for remote push notifications — CloudKit uses silent
                // pushes to tell the app "new data available, please fetch"
                UIApplication.shared.registerForRemoteNotifications()
                
                #if DEBUG
                CloudKitResetUtility.logContainerInfo()
                #endif
                
                // Start app initialization (lightweight — shows UI quickly)
                await startup.start()
                
                // Complete data protection with model context
                await startup.completeDataProtectionWithContext(sharedModelContainer.mainContext)
                
                //  Deferred heavy work — runs AFTER UI is visible
                await performDeferredBackup()
                
                // CloudKit cleanup runs after backup so UI is already showing
                await performAggressiveCloudKitCleanup()
            }
            .environmentObject(userPreferences)
            .alert(" Data Issue Detected", isPresented: $startup.showDataLossAlert) {
                Button("Open Data Safety") {
                    // User will navigate to Settings  Data Safety manually
                }
                Button("Dismiss", role: .cancel) { }
            } message: {
                Text(startup.dataLossDetails)
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background:
                print(" [AppLifecycle] App moved to background")
                // Save any pending changes before going to background
                do {
                    if sharedModelContainer.mainContext.hasChanges {
                        try sharedModelContainer.mainContext.save()
                        print(" [AppLifecycle] Saved pending changes to background")
                    }
                } catch {
                    print(" [AppLifecycle] Failed to save on background: \(error)")
                    DataOperationLogger.shared.logError(error, operation: "BackgroundSave")
                }
                
                // Push any local settings changes to iCloud
                iCloudKeyValueStore.shared.pushToCloud()
                
            case .active:
                print(" [AppLifecycle] App became active")
                // Pull latest settings from iCloud
                iCloudKeyValueStore.shared.pullFromCloud()
                
                // CRITICAL: Post remote change notification to trigger SwiftData
                // to check for and merge any pending CloudKit changes.
                // This is the primary mechanism for cross-device sync on app resume.
                NotificationCenter.default.post(
                    name: .NSPersistentStoreRemoteChange,
                    object: nil
                )
                
                // Save to trigger SwiftData to merge any pending remote changes into the UI
                do {
                    try sharedModelContainer.mainContext.save()
                    print(" [AppLifecycle] Context refreshed on foreground")
                } catch {
                    print(" [AppLifecycle] Failed to save on foreground: \(error)")
                    DataOperationLogger.shared.logError(error, operation: "ForegroundSave")
                }
                
                // Ensure notifications are scheduled
                NotificationManager.shared.scheduleIfNeeded()
                
                // Always trigger a sync check when app becomes active
                // This ensures cross-device changes are picked up immediately
                Task { @MainActor in
                    let syncService = iCloudSyncService.shared
                    if syncService.isSyncEnabled {
                        // Check if iCloud is available before syncing
                        let available = await syncService.checkiCloudAvailability()
                        if available {
                            await syncService.syncNow()
                            print(" [AppLifecycle] Triggered sync on app activation")
                        }
                    }
                }
                
            case .inactive:
                print(" [AppLifecycle] App became inactive")
                // Quick save to preserve any in-flight changes
                if sharedModelContainer.mainContext.hasChanges {
                    do {
                        try sharedModelContainer.mainContext.save()
                    } catch {
                        print(" [AppLifecycle] Failed to save on inactive: \(error)")
                    }
                }
                
            @unknown default:
                print(" [AppLifecycle] Unknown scene phase: \(scenePhase)")
            }
        }
    }
    
    /// Performs the emergency backup on a background thread AFTER the app
    /// has finished launching. This was previously done synchronously in the
    /// ModelContainer initializer, which caused watchdog timeout (code 9).
    private func performDeferredBackup() async {
        await Task.detached(priority: .utility) {
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            let lastEmergencyBackupKey = "lastEmergencyBackupTimestamp"
            let lastBackupTimestamp = UserDefaults.standard.double(forKey: lastEmergencyBackupKey)
            let hoursSinceLastBackup = (Date().timeIntervalSince1970 - lastBackupTimestamp) / 3600
            
            guard FileManager.default.fileExists(atPath: storeURL.path),
                  hoursSinceLastBackup >= 24 else { return }
            
            let timestamp = Int(Date().timeIntervalSince1970)
            let emergencyBackupURL = URL.applicationSupportDirectory
                .appending(path: "emergency_backup_\(timestamp).store")
            
            do {
                try FileManager.default.copyItem(at: storeURL, to: emergencyBackupURL)
                for ext in ["-shm", "-wal"] {
                    let src = URL(fileURLWithPath: storeURL.path + ext)
                    let dst = URL(fileURLWithPath: emergencyBackupURL.path + ext)
                    if FileManager.default.fileExists(atPath: src.path) {
                        try FileManager.default.copyItem(at: src, to: dst)
                    }
                }
                // Also back up external storage directory (photos, etc.)
                let externalSrc = URL(fileURLWithPath: storeURL.path + "_Files")
                let externalDst = URL(fileURLWithPath: emergencyBackupURL.path + "_Files")
                if FileManager.default.fileExists(atPath: externalSrc.path) {
                    try FileManager.default.copyItem(at: externalSrc, to: externalDst)
                }
                print(" [DataProtection] Deferred emergency backup created")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastEmergencyBackupKey)
            } catch {
                print(" [DataProtection] Could not create emergency backup: \(error)")
            }
            
            // Clean up old backups — file I/O only, safe off main thread
            await DataProtectionService.shared.cleanupEmergencyBackups()
        }.value
    }
    
    /// One-time CloudKit cleanup — deletes the corrupted zone so CoreData
    /// can re-export every local record with correct REFERENCE fields.
    private func performAggressiveCloudKitCleanup() async {
        let key = CloudKitResetUtility.cleanupVersionKey
        guard !UserDefaults.standard.bool(forKey: key) else {
            print(" [CloudKit] Schema cleanup already completed (\(key))")
            return
        }
        
        print(" [CloudKit] Starting schema-mismatch repair...")
        
        do {
            try await CloudKitResetUtility.repairCorruptedZone()
            print(" [CloudKit] Schema repair succeeded")
        } catch {
            print(" [CloudKit] Repair error (will retry next launch): \(error.localizedDescription)")
        }
    }
}
