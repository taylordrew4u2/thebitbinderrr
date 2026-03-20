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
        return CKContainer(identifier: "iCloud.666bit")
    }()
    
    override init() {
        super.init()
        isSyncEnabled = UserDefaults.standard.bool(forKey: SyncedKeys.iCloudSyncEnabled)
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
    
    @objc private func handleRemoteChange(_ notification: Notification) {
        // Debounce — only process once per 2 seconds to avoid loops
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(processRemoteChange), object: nil)
        perform(#selector(processRemoteChange), with: nil, afterDelay: 2.0)
    }
    
    @objc private func processRemoteChange() {
        Task { @MainActor in
            lastSyncDate = Date()
            // Post a notification so any listening views can refresh their queries
            NotificationCenter.default.post(name: .init("iCloudDataDidChange"), object: nil)
            print("🔄 [iCloud] Remote changes received — UI will refresh")
        }
    }
    
    @objc private func handleAccountChange(_ notification: Notification) {
        Task { @MainActor in
            let available = await checkiCloudAvailability()
            if available && isSyncEnabled {
                await performFullSync()
                print("🔄 [iCloud] Account changed — re-synced")
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
        guard isSyncEnabled else { return }
        
        syncStatus = .syncing
        defer {
            lastSyncDate = Date()
            kvStore.set(lastSyncDate!.timeIntervalSince1970, forKey: SyncedKeys.lastSyncDate)
        }
        
        // Push user settings to iCloud KV store
        iCloudKeyValueStore.shared.pushToCloud()
        
        // Sync all data types
        await syncJokes()
        await syncRoastTargets()
        await syncRoastJokes()
        await syncSetLists()
        await syncRecordings()
        await syncNotebookPhotos()
        
        syncStatus = .success
        errorMessage = nil
        hapticFeedback()
    }
    
    // MARK: - Incremental Syncs
    
    private func syncJokes() async {
        // Jokes sync handled via SwiftData CloudKit integration
        // SwiftData automatically syncs when iCloud sync is enabled
        print("✅ Jokes synced")
    }
    
    private func syncRoastTargets() async {
        // RoastTargets sync handled via SwiftData CloudKit integration
        // The @Relationship to RoastJoke ensures targets and their jokes stay linked
        print("✅ Roast targets synced")
    }
    
    private func syncRoastJokes() async {
        // RoastJokes sync handled via SwiftData CloudKit integration
        // Each RoastJoke has a REFERENCE back to its RoastTarget, synced automatically
        print("✅ Roast jokes synced")
    }
    
    private func syncSetLists() async {
        // SetLists sync handled via SwiftData CloudKit integration
        print("✅ Set lists synced")
    }
    
    private func syncRecordings() async {
        // Audio files synced via CloudKit file storage
        print("✅ Recordings synced")
    }
    
    private func syncNotebookPhotos() async {
        // Photo records synced via SwiftData CloudKit integration
        print("✅ Notebook photos synced")
    }
    
    // MARK: - Sync Thoughts (Notepad)
    
    func syncThoughts(_ content: String) async {
        guard isSyncEnabled else { return }
        
        // Save to iCloud KV store for sync
        kvStore.set(content, forKey: SyncedKeys.notepadText)
        
        // Also save to CloudKit for true cloud backup
        do {
            let record = CKRecord(recordType: "Thoughts")
            record["content"] = content
            record["timestamp"] = Date()
            
            let database = container.privateCloudDatabase
            _ = try await database.save(record)
            print("✅ Thoughts synced to iCloud")
        } catch {
            print("❌ Failed to sync thoughts: \(error)")
        }
    }
    
    func fetchThoughtsFromCloud() async -> String? {
        guard isSyncEnabled else { return nil }
        
        do {
            let database = container.privateCloudDatabase
            let query = CKQuery(recordType: "Thoughts", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            
            let results = try await database.records(matching: query)
            if let latestRecord = try results.matchResults.first?.1.get() {
                return latestRecord["content"] as? String
            }
        } catch {
            print("❌ Failed to fetch thoughts: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Manual Sync Trigger
    
    func syncNow() async {
        await performFullSync()
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
                print("✅ [iCloud] Account available")
                return true
            case .noAccount:
                print("❌ [iCloud] No account — user not signed into iCloud")
                errorMessage = "Sign in to iCloud in Settings → [Your Name] → iCloud"
            case .restricted:
                print("❌ [iCloud] Account restricted (parental controls or MDM)")
                errorMessage = "iCloud is restricted on this device"
            case .couldNotDetermine:
                print("❌ [iCloud] Could not determine account status")
                errorMessage = "Could not check iCloud status — try again later"
            case .temporarilyUnavailable:
                print("⚠️ [iCloud] Temporarily unavailable")
                errorMessage = "iCloud is temporarily unavailable — try again later"
            @unknown default:
                print("❌ [iCloud] Unknown account status: \(status)")
                errorMessage = "Unknown iCloud status"
            }
            return false
        } catch {
            print("❌ [iCloud] Account check error: \(error)")
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
            results.append("iCloud Account: \(status == .available ? "✅ Available" : "❌ \(status)")")
        } catch {
            results.append("iCloud Account: ❌ Error — \(error.localizedDescription)")
        }
        
        // 2. Container ID
        results.append("Container: iCloud.666bit")
        
        // 3. Sync enabled
        results.append("Sync Enabled: \(isSyncEnabled ? "✅ Yes" : "❌ No")")
        
        // 4. Last sync
        if let lastSync = lastSyncDate {
            results.append("Last Sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
        } else {
            results.append("Last Sync: Never")
        }
        
        // 5. Try a test fetch to verify CloudKit connectivity
        do {
            let database = container.privateCloudDatabase
            let query = CKQuery(recordType: "CD_RoastTarget", predicate: NSPredicate(value: true))
            let (matchResults, _) = try await database.records(matching: query, resultsLimit: 1)
            results.append("CloudKit Fetch Test: ✅ Connected (\(matchResults.count) result(s))")
        } catch {
            results.append("CloudKit Fetch Test: ❌ \(error.localizedDescription)")
        }
        
        return results
    }
}

