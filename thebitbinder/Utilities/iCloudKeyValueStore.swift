//
//  iCloudKeyValueStore.swift
//  thebitbinder
//
//  Bridges NSUbiquitousKeyValueStore (iCloud KV) with UserDefaults so
//  @AppStorage and manual UserDefaults reads stay in sync across devices.
//

import Foundation
import Combine

/// Keys that should be synced to iCloud across devices
enum SyncedKeys {
    // User preferences
    static let notepadText       = "notepadText"
    static let roastModeEnabled  = "roastModeEnabled"
    static let roastViewMode     = "roastViewMode"
    static let tabOrder          = "tabOrder"
    static let jokesViewMode     = "jokesViewMode"
    static let jokesGridScale    = "jokesGridScale"
    static let roastGridScale    = "roastGridScale"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
    static let showFullContent   = "showFullContent"
    static let autoOrganizeEnabled = "autoOrganizeEnabled"
    
    // Notification settings
    static let dailyNotificationsEnabled = "dailyNotificationsEnabled"
    static let dailyNotifStartMinute = "dailyNotifStartMinute"
    static let dailyNotifEndMinute = "dailyNotifEndMinute"
    
    // Auth
    static let termsAccepted = "hasAcceptedTerms"
    static let userId = "userId"
    static let lastSyncDate = "lastSyncDate"
    
    /// All keys that should be mirrored between UserDefaults and iCloud KV store
    static let all: [String] = [
        notepadText,
        roastModeEnabled,
        roastViewMode,
        tabOrder,
        jokesViewMode,
        jokesGridScale,
        roastGridScale,
        iCloudSyncEnabled,
        showFullContent,
        autoOrganizeEnabled,
        dailyNotificationsEnabled,
        dailyNotifStartMinute,
        dailyNotifEndMinute,
        termsAccepted,
        userId,
        lastSyncDate,
    ]
}

/// Singleton that keeps UserDefaults and NSUbiquitousKeyValueStore in sync.
/// On launch it pulls from iCloud  local. On local writes it pushes to iCloud.
/// Also observes UserDefaults so @AppStorage changes are pushed automatically.
final class iCloudKeyValueStore {
    static let shared = iCloudKeyValueStore()
    
    private let cloud = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard
    /// Prevents feedback loops when pulling from cloud triggers local observation
    private var isSyncing = false
    
    /// Performance: Debounce sync operations
    private var syncDebounceWorkItem: DispatchWorkItem?
    
    private init() {
        // Listen for remote changes pushed from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )
        
        // Watch for UserDefaults.standard changes and auto-push synced keys to iCloud
        // This catches @AppStorage writes which bypass our set() methods.
        // NOTE: Must pass `object: local` (not nil) — passing nil observes ALL
        // UserDefaults domains including app group suites, which triggers:
        // "Using kCFPreferencesAnyUser with a container is only allowed for System Containers"
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: local
        )
        
        // Trigger initial sync from iCloud
        cloud.synchronize()
        pullFromCloud()
    }
    
    // MARK: - Write (local  iCloud)
    
    /// Set a string value and push to iCloud
    func set(_ value: String?, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value, forKey: key)
        cloud.synchronize()
    }
    
    /// Set a bool value and push to iCloud
    func set(_ value: Bool, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value, forKey: key)
        cloud.synchronize()
    }
    
    /// Set a Data value and push to iCloud
    func set(_ value: Data, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value, forKey: key)
        cloud.synchronize()
    }
    
    /// Set an integer value and push to iCloud
    func set(_ value: Int, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value as NSNumber, forKey: key)
        cloud.synchronize()
    }
    
    /// Set a double value and push to iCloud
    func set(_ value: Double, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value as NSNumber, forKey: key)
        cloud.synchronize()
    }
    
    // MARK: - Read (offline-first: local has priority for immediate access)
    
    func string(forKey key: String) -> String? {
        // Local first for offline support, cloud syncs in background
        local.string(forKey: key) ?? cloud.string(forKey: key)
    }
    
    func bool(forKey key: String) -> Bool {
        // Local first for offline support
        local.bool(forKey: key)
    }
    
    func data(forKey key: String) -> Data? {
        local.data(forKey: key) ?? cloud.data(forKey: key)
    }
    
    func integer(forKey key: String) -> Int {
        local.integer(forKey: key)
    }
    
    func double(forKey key: String) -> Double {
        local.double(forKey: key)
    }
    
    // MARK: - Auto-push on UserDefaults change
    
    /// Called whenever ANY UserDefaults key changes (including @AppStorage)
    @objc private func defaultsDidChange() {
        guard !isSyncing else { return }  // Don't push back what we just pulled
        
        // Performance: Debounce sync operations to prevent excessive iCloud calls
        syncDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSyncToCloud()
        }
        syncDebounceWorkItem = workItem
        // Reduced debounce time for better responsiveness
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
    
    /// Performs the actual sync to iCloud (debounced)
    private func performSyncToCloud() {
        guard !isSyncing else { return }
        
        var changed = false
        var changedKeys: [String] = []
        
        for key in SyncedKeys.all {
            let localValue = local.object(forKey: key)
            let cloudValue = cloud.object(forKey: key)
            
            // Compare and push if different
            if !valuesEqual(localValue, cloudValue) {
                if let val = localValue {
                    cloud.set(val, forKey: key)
                    print(" [iCloudKV] Updated cloud key: \(key)")
                } else {
                    cloud.removeObject(forKey: key)
                    print(" [iCloudKV] Removed cloud key: \(key)")
                }
                changedKeys.append(key)
                changed = true
            }
        }
        
        if changed {
            let success = cloud.synchronize()
            if success {
                print(" [iCloudKV] Auto-synced \(changedKeys.count) changed keys to iCloud: \(changedKeys.joined(separator: ", "))")
            } else {
                print(" [iCloudKV] Failed to sync \(changedKeys.count) keys to iCloud")
            }
        }
    }
    
    /// Simple equality check for plist-compatible values
    private func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a as String, b as String): return a == b
        case let (a as Bool, b as Bool): return a == b
        case let (a as Int, b as Int): return a == b
        case let (a as Double, b as Double): return a == b
        case let (a as Data, b as Data): return a == b
        default:
            // Fallback: compare descriptions
            return String(describing: a) == String(describing: b)
        }
    }
    
    // MARK: - Pull (iCloud  local)
    
    /// Pull all synced keys from iCloud into UserDefaults
    func pullFromCloud() {
        isSyncing = true
        defer { isSyncing = false }
        
        for key in SyncedKeys.all {
            if let cloudValue = cloud.object(forKey: key) {
                local.set(cloudValue, forKey: key)
            }
        }
        // Note: synchronize() is deprecated since iOS 12 — UserDefaults
        // auto-saves changes. Removing to avoid console warnings.
        print(" [iCloudKV] Pulled \(SyncedKeys.all.count) keys from iCloud")
    }
    
    /// Push all synced keys from UserDefaults to iCloud
    func pushToCloud() {
        for key in SyncedKeys.all {
            if let localValue = local.object(forKey: key) {
                cloud.set(localValue, forKey: key)
            }
        }
        cloud.synchronize()
        print(" [iCloudKV] Pushed \(SyncedKeys.all.count) keys to iCloud")
    }
    
    // MARK: - Remote Change Handler
    
    @objc private func cloudDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            print(" [iCloudKV] Remote change received but no reason key — ignoring")
            return
        }
        
        let reasonString: String
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange:
            reasonString = "ServerChange"
        case NSUbiquitousKeyValueStoreInitialSyncChange:
            reasonString = "InitialSync"
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            reasonString = "QuotaViolation"
            print(" ⚠️ [iCloudKV] QUOTA VIOLATION — iCloud KV store quota exceeded! Some keys may not sync.")
        case NSUbiquitousKeyValueStoreAccountChange:
            reasonString = "AccountChange"
            print(" [iCloudKV] iCloud account changed — user may have signed in/out")
        default:
            reasonString = "Unknown(\(reason))"
        }
        
        // Only process server changes and initial syncs
        if reason == NSUbiquitousKeyValueStoreServerChange ||
           reason == NSUbiquitousKeyValueStoreInitialSyncChange {
            
            isSyncing = true
            defer { isSyncing = false }
            
            let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            let syncedChangedKeys = changedKeys.filter { SyncedKeys.all.contains($0) }
            
            var successCount = 0
            for key in syncedChangedKeys {
                if let value = cloud.object(forKey: key) {
                    local.set(value, forKey: key)
                    successCount += 1
                } else {
                    // Key was removed from cloud
                    local.removeObject(forKey: key)
                    successCount += 1
                }
            }
            
            if successCount > 0 {
                local.synchronize()
                print(" [iCloudKV] Successfully synced \(successCount) keys from \(reasonString)")
                
                // Post notification so views can refresh
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .iCloudKVDidChange, 
                        object: nil, 
                        userInfo: ["keys": syncedChangedKeys, "reason": reasonString]
                    )
                }
            }
            
            print(" [iCloudKV] Received \(reasonString) for \(changedKeys.count) key(s), \(syncedChangedKeys.count) synced: \(syncedChangedKeys.joined(separator: ", "))")
        } else {
            print(" [iCloudKV] Received \(reasonString) — no action taken")
        }
    }
    
    // MARK: - Debug & Diagnostics
    
    /// Forces a full iCloud KV store synchronization cycle (pull + push).
    /// Useful for debugging sync issues from Settings.
    func forceSync() {
        print(" [iCloudKV] Force sync initiated...")
        
        // Force Apple to sync with iCloud servers
        let syncResult = cloud.synchronize()
        print(" [iCloudKV] synchronize() returned: \(syncResult)")
        
        // Pull any changes from cloud  local
        pullFromCloud()
        
        // Push any local changes to cloud
        pushToCloud()
        
        print(" [iCloudKV] Force sync completed")
    }
    
    /// Returns diagnostic information about the current KV store state.
    func diagnostics() -> [String] {
        var results: [String] = []
        
        results.append(" iCloud KV Store Diagnostics ")
        
        for key in SyncedKeys.all {
            let localVal = local.object(forKey: key)
            let cloudVal = cloud.object(forKey: key)
            let match = valuesEqual(localVal, cloudVal)
            let localStr = localVal.map { "\($0)" } ?? "nil"
            let cloudStr = cloudVal.map { "\($0)" } ?? "nil"
            let status = match ? "" : " MISMATCH"
            results.append("\(status) \(key): local=\(localStr.prefix(40)) | cloud=\(cloudStr.prefix(40))")
        }
        
        return results
    }
}

// MARK: - Notification

extension Notification.Name {
    static let iCloudKVDidChange = Notification.Name("iCloudKVDidChange")
}
