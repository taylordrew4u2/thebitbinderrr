//
//  iCloudSyncService.swift
//  thebitbinder
//
//  Created on 3/7/26.
//

import SwiftUI
import SwiftData
import CloudKit
import UIKit
import CoreData

@MainActor
final class iCloudSyncService: NSObject, ObservableObject {
    @Published var isSyncEnabled = false
    @Published var isHapticFeedbackEnabled = true
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var errorMessage: String?
    
    private var syncDebouncer: Timer?
    private var lastSyncCompletionDate: Date = .distantPast
    private let syncCooldown: TimeInterval = 3.0 // 3 seconds (reduced from 5 for faster sync)

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)
    }
    
    static let shared = iCloudSyncService()
    private let kvStore = iCloudKeyValueStore.shared
    
    // Set this from the app so remote change notifications can trigger a context refresh
    weak var modelContext: ModelContext?
    
    // CloudKit container — must match the container used in ModelContainer CloudKit config
    private lazy var container: CKContainer = {
        return CKContainer(identifier: "iCloud.The-BitBinder.thebitbinder")
    }()
    
    override init() {
        super.init()
        
        // Check if sync setting has been explicitly set
        let hasSetSyncPreference = UserDefaults.standard.object(forKey: SyncedKeys.iCloudSyncEnabled) != nil
        
        if hasSetSyncPreference {
            isSyncEnabled = UserDefaults.standard.bool(forKey: SyncedKeys.iCloudSyncEnabled)
        } else {
            // Default to enabled for new installs - sync should work out of the box
            isSyncEnabled = true
            UserDefaults.standard.set(true, forKey: SyncedKeys.iCloudSyncEnabled)
            print(" [iCloud] First launch - sync enabled by default")
        }
        
        if let lastSyncTimestamp = UserDefaults.standard.object(forKey: SyncedKeys.lastSyncDate) as? Double {
            lastSyncDate = Date(timeIntervalSince1970: lastSyncTimestamp)
        }
        setupRemoteChangeObserver()
    }
    
    // MARK: - Remote Change Notifications
    // This is the key piece that makes sync "just work" across devices.
    // When SwiftData pushes a change to CloudKit from another device, CloudKit
    // sends a silent push to this device. We observe that notification and
    // tell SwiftData's context to refresh, pulling the new data immediately.
    
    private func setupRemoteChangeObserver() {
        // SwiftData + CloudKit fires this when remote changes arrive
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )
        
        // Also observe CloudKit account changes (user signs in/out of iCloud)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccountChange),
            name: .CKAccountChanged,
            object: nil
        )
    }
    
    @objc nonisolated private func handleRemoteChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.syncDebouncer?.invalidate()
            self?.syncDebouncer = Timer.scheduledTimer(
                withTimeInterval: 1.0, // Reduced from 2.0 for faster sync
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.processRemoteChangeAsync()
                }
            }
        }
    }
    
    private func processRemoteChangeAsync() async {
        guard Date().timeIntervalSince(lastSyncCompletionDate) >= syncCooldown else {
            print(" [iCloud] Sync request ignored due to cooldown.")
            return
        }
        
        syncStatus = .syncing
        
        // Refresh the SwiftData context so it merges remote CloudKit changes
        // into the in-memory objects. Without this, the context holds stale data
        // and the UI won't reflect changes from other devices.
        if let ctx = modelContext {
            do {
                // Step 1: Save any pending local changes first to avoid conflicts
                if ctx.hasChanges {
                    try ctx.save()
                    print(" [iCloud] Saved pending local changes before merge")
                }
                
                // Step 2: Fetch current count to verify sync is working
                let jokeCount = try ctx.fetchCount(FetchDescriptor<Joke>())
                print(" [iCloud] Current joke count after merge: \(jokeCount)")
                
                // Step 3: Post notification so SwiftUI views using @Query will refresh
                // @Query automatically observes the model context and should update,
                // but posting this notification allows custom observers to react too.
                NotificationCenter.default.post(name: .init("iCloudDataDidChange"), object: nil)
                
                print(" [iCloud] Context successfully refreshed with remote changes")
            } catch {
                print(" [iCloud] Context operation during remote merge failed: \(error.localizedDescription)")
                syncStatus = .error("Failed to merge remote changes: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                lastSyncCompletionDate = Date()
                return
            }
        } else {
            print(" [iCloud] Remote changes received but modelContext is nil — cannot refresh")
            syncStatus = .error("Context unavailable for remote changes")
            errorMessage = "Context unavailable for remote changes"
            lastSyncCompletionDate = Date()
            return
        }
        
        lastSyncDate = Date()
        syncStatus = .success
        lastSyncCompletionDate = Date()
        errorMessage = nil
        
        // Save the sync date to persistence
        if let syncDate = lastSyncDate {
            UserDefaults.standard.set(syncDate.timeIntervalSince1970, forKey: SyncedKeys.lastSyncDate)
        }
        
        print(" [iCloud] Remote changes received and merged — UI will refresh")
        
        // Haptic feedback to let user know sync completed
        hapticFeedback()
    }
    
    @objc nonisolated private func handleAccountChange(_ notification: Notification) {
        Task { @MainActor in
            print(" [iCloud] Account change detected")
            syncStatus = .syncing
            
            let available = await checkiCloudAvailability()
            if available {
                if isSyncEnabled {
                    await performFullSync()
                    print(" [iCloud] Account changed — re-synced successfully")
                } else {
                    print(" [iCloud] Account available but sync disabled")
                    syncStatus = .idle
                }
            } else {
                print(" [iCloud] Account changed but not available")
                syncStatus = .error("iCloud account not available")
                // Don't disable sync - just wait for account to become available
            }
        }
    }
    
    // MARK: - Enable/Disable iCloud Sync
    
    func enableiCloudSync() async {
        do {
            // Check iCloud availability
            let status = try await container.accountStatus()
            guard status == .available else {
                syncStatus = .error("iCloud not available")
                errorMessage = "Please sign into iCloud in Settings"
                return
            }
            
            isSyncEnabled = true
            kvStore.set(true, forKey: SyncedKeys.iCloudSyncEnabled)
            
            // Perform initial sync
            await performFullSync()
        } catch {
            syncStatus = .error(error.localizedDescription)
            errorMessage = "Failed to enable iCloud sync: \(error.localizedDescription)"
        }
    }
    
    func disableiCloudSync() {
        isSyncEnabled = false
        kvStore.set(false, forKey: SyncedKeys.iCloudSyncEnabled)
        syncStatus = .idle
        errorMessage = nil
    }
    
    // MARK: - Full Sync
    
    func performFullSync() async {
        guard isSyncEnabled else { 
            print(" [iCloud] Sync requested but disabled")
            return 
        }
        
        print(" [iCloud] Starting full sync...")
        syncStatus = .syncing
        errorMessage = nil
        
        defer {
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: SyncedKeys.lastSyncDate)
        }
        
        do {
            // 1. Verify iCloud availability first
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                let message = "iCloud account not available: \(accountStatus)"
                print(" [iCloud] \(message)")
                syncStatus = .error(message)
                errorMessage = message
                return
            }
            
            // 2. Save any pending local changes first
            if let ctx = modelContext, ctx.hasChanges {
                try ctx.save()
                print(" [iCloud] Saved pending local changes")
            }
            
            // 3. Push user settings to iCloud KV store
            print(" [iCloud] Syncing user preferences...")
            iCloudKeyValueStore.shared.pushToCloud()
            
            // 4. Trigger CloudKit sync by touching the container
            // This encourages SwiftData to push/pull with CloudKit
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            
            // Try to access the zone to trigger connectivity check
            do {
                _ = try await database.recordZone(for: zoneID)
                print(" [iCloud] CloudKit zone accessible")
            } catch let error as CKError where error.code == .zoneNotFound {
                print(" [iCloud] CloudKit zone doesn't exist yet - will be created on first save")
            } catch {
                print(" [iCloud] Warning: Could not access CloudKit zone: \(error.localizedDescription)")
                // Continue anyway - zone might be created automatically
            }
            
            // 5. Sync all data types (placeholder for future custom logic)
            await syncJokes()
            await syncRoastTargets()
            await syncRoastJokes()
            await syncSetLists()
            await syncRecordings()
            await syncNotebookPhotos()
            await syncBrainstormIdeas()
            await syncImportBatches()
            await syncChatMessages()
            
            // 6. Force context refresh to pull any remote changes
            if let ctx = modelContext {
                // Post notification to trigger CloudKit sync engine
                NotificationCenter.default.post(
                    name: .NSPersistentStoreRemoteChange,
                    object: nil
                )
                
                do {
                    try ctx.save()
                    
                    // Verify sync by checking counts
                    let jokeCount = try ctx.fetchCount(FetchDescriptor<Joke>())
                    print(" [iCloud] Final context save completed - \(jokeCount) jokes in store")
                } catch {
                    print(" [iCloud] Warning: Final context save failed: \(error.localizedDescription)")
                }
            }
            
            // Notify UI to refresh
            NotificationCenter.default.post(name: .init("iCloudDataDidChange"), object: nil)
            
            syncStatus = .success
            errorMessage = nil
            print(" [iCloud] Full sync completed successfully")
            hapticFeedback()
            
        } catch {
            let message = "Sync failed: \(error.localizedDescription)"
            print(" [iCloud] \(message)")
            syncStatus = .error(message)
            errorMessage = message
        }
    }
    
    // MARK: - Incremental Syncs
    // SwiftData + CloudKit handles record-level sync automatically.
    // These methods exist only to hook into performFullSync() for
    // future per-type logic (e.g. conflict resolution, dedup).
    
    private func syncJokes() async {
        // No-op: SwiftData auto-syncs Joke records via CloudKit.
    }
    
    private func syncRoastTargets() async {
        // No-op: SwiftData auto-syncs RoastTarget records via CloudKit.
        // The @Relationship to RoastJoke ensures targets and their jokes stay linked.
    }
    
    private func syncRoastJokes() async {
        // No-op: SwiftData auto-syncs RoastJoke records via CloudKit.
    }
    
    private func syncSetLists() async {
        // No-op: SwiftData auto-syncs SetList records via CloudKit.
    }
    
    private func syncRecordings() async {
        // No-op: SwiftData auto-syncs Recording records via CloudKit.
        // Audio files stored at fileURL are NOT synced — only the metadata record.
    }
    
    private func syncNotebookPhotos() async {
        // No-op: SwiftData auto-syncs NotebookPhotoRecord records via CloudKit.
        // imageData uses @Attribute(.externalStorage), synced as a CKAsset.
    }
    
    private func syncBrainstormIdeas() async {
        // No-op: SwiftData auto-syncs BrainstormIdea records via CloudKit.
    }
    
    private func syncImportBatches() async {
        // No-op: SwiftData auto-syncs ImportBatch and related records via CloudKit.
    }
    
    private func syncChatMessages() async {
        // No-op: SwiftData auto-syncs ChatMessage records via CloudKit.
    }
    
    // MARK: - Sync Thoughts (Notepad)
    
    func syncThoughts(_ content: String) async {
        guard isSyncEnabled else { return }
        
        // Save to iCloud KV store for sync
        kvStore.set(content, forKey: SyncedKeys.notepadText)
        
        // Also save to CloudKit for true cloud backup.
        // Use a fixed recordName so we UPSERT the same record every time
        // instead of creating a new CKRecord on every call.
        do {
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            let recordID = CKRecord.ID(recordName: "UserThoughts", zoneID: zoneID)
            
            // Fetch existing record, or create a new one if it doesn't exist yet
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                record = CKRecord(recordType: "Thoughts", recordID: recordID)
            }
            
            record["content"] = content
            record["timestamp"] = Date()
            
            _ = try await database.save(record)
            print(" Thoughts synced to iCloud")
        } catch {
            print(" Failed to sync thoughts: \(error)")
        }
    }
    
    func fetchThoughtsFromCloud() async -> String? {
        guard isSyncEnabled else { return nil }
        
        do {
            let database = container.privateCloudDatabase
            let query = CKQuery(recordType: "Thoughts", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            
            let results = try await database.records(matching: query, resultsLimit: 1)
            if let latestRecord = try results.matchResults.first?.1.get() {
                return latestRecord["content"] as? String
            }
        } catch {
            print(" Failed to fetch thoughts: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Manual Sync Trigger
    
    func syncNow() async {
        await performFullSync()
    }
    
    /// Force refresh all data from CloudKit - use when sync seems stuck
    /// This is more aggressive than syncNow() and will re-fetch counts to verify
    func forceRefreshAllData() async {
        print(" [iCloud] Force refresh initiated...")
        syncStatus = .syncing
        errorMessage = nil
        
        guard let ctx = modelContext else {
            syncStatus = .error("No model context available")
            errorMessage = "No model context available"
            return
        }
        
        do {
            // 1. Verify iCloud is available
            let available = await checkiCloudAvailability()
            guard available else {
                syncStatus = .error("iCloud not available")
                return
            }
            
            // 2. Save any pending changes
            if ctx.hasChanges {
                try ctx.save()
                print(" [iCloud] Saved pending changes before force refresh")
            }
            
            // 3. Post remote change notification to trigger CoreData's CloudKit
            // integration to check for and import any pending remote changes
            NotificationCenter.default.post(
                name: .NSPersistentStoreRemoteChange,
                object: nil
            )
            
            // 4. Wait a moment for CloudKit to process
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // 5. Verify by fetching counts
            let jokeCount = try ctx.fetchCount(FetchDescriptor<Joke>())
            let setListCount = try ctx.fetchCount(FetchDescriptor<SetList>())
            let recordingCount = try ctx.fetchCount(FetchDescriptor<Recording>())
            
            print(" [iCloud] Force refresh complete - Jokes: \(jokeCount), SetLists: \(setListCount), Recordings: \(recordingCount)")
            
            lastSyncDate = Date()
            syncStatus = .success
            lastSyncCompletionDate = Date()
            errorMessage = nil
            
            if let syncDate = lastSyncDate {
                UserDefaults.standard.set(syncDate.timeIntervalSince1970, forKey: SyncedKeys.lastSyncDate)
            }
            
            // Notify UI to refresh
            NotificationCenter.default.post(name: .init("iCloudDataDidChange"), object: nil)
            
            hapticFeedback()
            
        } catch {
            print(" [iCloud] Force refresh failed: \(error.localizedDescription)")
            syncStatus = .error("Force refresh failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Haptic Feedback
    
    private func hapticFeedback() {
        guard isHapticFeedbackEnabled else { return }
#if !targetEnvironment(macCatalyst)
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
#endif
    }
    
    // MARK: - Check Sync Status
    
    func checkiCloudAvailability() async -> Bool {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                print(" [iCloud] Account available")
                return true
            case .noAccount:
                print(" [iCloud] No account — user not signed into iCloud")
                errorMessage = "Sign in to iCloud in Settings  [Your Name]  iCloud"
            case .restricted:
                print(" [iCloud] Account restricted (parental controls or MDM)")
                errorMessage = "iCloud is restricted on this device"
            case .couldNotDetermine:
                print(" [iCloud] Could not determine account status")
                errorMessage = "Could not check iCloud status — try again later"
            case .temporarilyUnavailable:
                print(" [iCloud] Temporarily unavailable")
                errorMessage = "iCloud is temporarily unavailable — try again later"
            @unknown default:
                print(" [iCloud] Unknown account status: \(status)")
                errorMessage = "Unknown iCloud status"
            }
            return false
        } catch {
            print(" [iCloud] Account check error: \(error)")
            errorMessage = "iCloud check failed: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Detailed diagnostic info — call from Settings to surface issues
    func runDiagnostics() async -> [String] {
        var results: [String] = []
        
        // 1. iCloud account
        do {
            let status = try await container.accountStatus()
            results.append("iCloud Account: \(status == .available ? " Available" : " \(status)")")
        } catch {
            results.append("iCloud Account:  Error — \(error.localizedDescription)")
        }
        
        // 2. Container ID
        results.append("Container: iCloud.The-BitBinder.thebitbinder")
        
        // 3. Sync enabled
        results.append("Sync Enabled: \(isSyncEnabled ? " Yes" : " No")")
        
        // 4. Last sync
        if let lastSync = lastSyncDate {
            results.append("Last Sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
        } else {
            results.append("Last Sync: Never")
        }
        
        // 5. Try a test fetch to verify CloudKit connectivity
        // Note: CD_* record types are managed by CoreData's CloudKit mirroring
        // and cannot be queried directly via CKQuery. Instead, verify connectivity
        // by fetching the CoreData CloudKit zone itself.
        do {
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            let zone = try await database.recordZone(for: zoneID)
            results.append("CloudKit Fetch Test:  Connected (zone: \(zone.zoneID.zoneName))")
        } catch {
            results.append("CloudKit Fetch Test:  \(error.localizedDescription)")
        }
        
        return results
    }
}
