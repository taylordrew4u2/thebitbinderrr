//
//  iCloudSyncDiagnostics.swift
//  thebitbinder
//
//  Created for debugging and fixing iCloud sync issues
//

import SwiftUI
import SwiftData
import CloudKit
import Foundation

@MainActor
final class iCloudSyncDiagnostics: ObservableObject {
    static let shared = iCloudSyncDiagnostics()
    
    @Published var isRunningDiagnostics = false
    @Published var diagnosticResults: [String] = []
    @Published var syncIssuesFound: [SyncIssue] = []
    
    private let container = CKContainer(identifier: "iCloud.The-BitBinder.thebitbinder")
    
    struct SyncIssue {
        let type: IssueType
        let description: String
        let severity: Severity
        let suggestedFix: String
        
        enum IssueType {
            case accountStatus
            case containerAccess
            case schemaVersion
            case recordTypeIssue
            case networkConnectivity
            case zoneConfiguration
            case pushNotifications
            case dataConsistency
        }
        
        enum Severity {
            case critical
            case warning
            case info
        }
    }
    
    private init() {}
    
    func runComprehensiveDiagnostics() async {
        isRunningDiagnostics = true
        diagnosticResults.removeAll()
        syncIssuesFound.removeAll()
        
        await checkAccountStatus()
        await checkContainerAccess()
        await checkPushNotifications()
        await checkZoneConfiguration()
        await checkSchemaConsistency()
        await checkDataConsistency()
        await checkKeyValueStore()
        
        isRunningDiagnostics = false
    }
    
    private func checkAccountStatus() async {
        diagnosticResults.append("🔍 Checking iCloud Account Status...")
        
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                diagnosticResults.append("✅ iCloud account available")
            case .noAccount:
                diagnosticResults.append("❌ No iCloud account signed in")
                syncIssuesFound.append(SyncIssue(
                    type: .accountStatus,
                    description: "User is not signed into iCloud",
                    severity: .critical,
                    suggestedFix: "Sign in to iCloud in Settings > [Your Name] > iCloud"
                ))
            case .restricted:
                diagnosticResults.append("⚠️ iCloud account restricted (parental controls or MDM)")
                syncIssuesFound.append(SyncIssue(
                    type: .accountStatus,
                    description: "iCloud access is restricted on this device",
                    severity: .critical,
                    suggestedFix: "Check parental controls or contact device administrator"
                ))
            case .couldNotDetermine:
                diagnosticResults.append("❓ Could not determine iCloud account status")
                syncIssuesFound.append(SyncIssue(
                    type: .accountStatus,
                    description: "Unable to determine iCloud status",
                    severity: .warning,
                    suggestedFix: "Try again later or restart the app"
                ))
            case .temporarilyUnavailable:
                diagnosticResults.append("⏳ iCloud temporarily unavailable")
                syncIssuesFound.append(SyncIssue(
                    type: .accountStatus,
                    description: "iCloud services are temporarily unavailable",
                    severity: .warning,
                    suggestedFix: "Wait and try again later"
                ))
            @unknown default:
                diagnosticResults.append("❓ Unknown iCloud status: \(status)")
                syncIssuesFound.append(SyncIssue(
                    type: .accountStatus,
                    description: "Unknown iCloud account status",
                    severity: .warning,
                    suggestedFix: "Update iOS and restart the app"
                ))
            }
        } catch {
            diagnosticResults.append("❌ Failed to check account status: \(error.localizedDescription)")
            syncIssuesFound.append(SyncIssue(
                type: .accountStatus,
                description: "Account status check failed: \(error.localizedDescription)",
                severity: .critical,
                suggestedFix: "Check internet connection and try again"
            ))
        }
    }
    
    private func checkContainerAccess() async {
        diagnosticResults.append("🔍 Checking CloudKit Container Access...")
        
        do {
            let database = container.privateCloudDatabase
            
            // Try to access the CoreData CloudKit zone
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            
            let zone = try await database.recordZone(for: zoneID)
            diagnosticResults.append("✅ CloudKit zone accessible: \(zone.zoneID.zoneName)")
            
        } catch let error as CKError {
            switch error.code {
            case .zoneNotFound:
                diagnosticResults.append("⚠️ CloudKit zone not found - will be created on first sync")
                syncIssuesFound.append(SyncIssue(
                    type: .zoneConfiguration,
                    description: "CloudKit zone doesn't exist yet",
                    severity: .info,
                    suggestedFix: "Zone will be created automatically on first data save"
                ))
            case .notAuthenticated:
                diagnosticResults.append("❌ Not authenticated with CloudKit")
                syncIssuesFound.append(SyncIssue(
                    type: .containerAccess,
                    description: "Not authenticated with CloudKit",
                    severity: .critical,
                    suggestedFix: "Sign out and back into iCloud"
                ))
            case .networkFailure, .networkUnavailable:
                diagnosticResults.append("❌ Network error accessing CloudKit")
                syncIssuesFound.append(SyncIssue(
                    type: .networkConnectivity,
                    description: "Network connectivity issue",
                    severity: .warning,
                    suggestedFix: "Check internet connection"
                ))
            default:
                diagnosticResults.append("❌ CloudKit access error: \(error.localizedDescription)")
                syncIssuesFound.append(SyncIssue(
                    type: .containerAccess,
                    description: "CloudKit access failed: \(error.localizedDescription)",
                    severity: .warning,
                    suggestedFix: "Try again later or contact support"
                ))
            }
        } catch {
            diagnosticResults.append("❌ Unexpected error: \(error.localizedDescription)")
            syncIssuesFound.append(SyncIssue(
                type: .containerAccess,
                description: "Unexpected container access error",
                severity: .warning,
                suggestedFix: "Restart the app and try again"
            ))
        }
    }
    
    private func checkPushNotifications() async {
        diagnosticResults.append("🔍 Checking Push Notification Registration...")
        
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authStatus = settings.authorizationStatus
        
        switch authStatus {
        case .authorized, .provisional:
            diagnosticResults.append("✅ Notifications authorized")
        case .denied:
            diagnosticResults.append("⚠️ Notifications denied - may affect sync timing")
            syncIssuesFound.append(SyncIssue(
                type: .pushNotifications,
                description: "Push notifications are disabled",
                severity: .warning,
                suggestedFix: "Enable notifications in Settings > The BitBinder > Notifications"
            ))
        case .notDetermined:
            diagnosticResults.append("❓ Notification permissions not determined")
        case .ephemeral:
            diagnosticResults.append("⚠️ Ephemeral notification authorization")
        @unknown default:
            diagnosticResults.append("❓ Unknown notification status")
        }
        
        // Check if remote notifications are registered
        // Already on @MainActor — no need for MainActor.run (avoids re-entrant unsafeForcedSync).
        if UIApplication.shared.isRegisteredForRemoteNotifications {
            diagnosticResults.append("✅ Registered for remote notifications")
        } else {
            diagnosticResults.append("❌ Not registered for remote notifications")
            syncIssuesFound.append(SyncIssue(
                type: .pushNotifications,
                description: "Remote notifications not registered",
                severity: .critical,
                suggestedFix: "App will re-register automatically on next launch"
            ))
        }
    }
    
    private func checkZoneConfiguration() async {
        diagnosticResults.append("🔍 Checking CloudKit Zone Configuration...")
        
        do {
            let database = container.privateCloudDatabase
            let zones = try await database.allRecordZones()
            
            diagnosticResults.append("📋 Found \(zones.count) CloudKit zones:")
            for zone in zones {
                diagnosticResults.append("  • \(zone.zoneID.zoneName)")
            }
            
            // Check if the CoreData zone exists
            let coreDataZone = zones.first { $0.zoneID.zoneName == "com.apple.coredata.cloudkit.zone" }
            if coreDataZone != nil {
                diagnosticResults.append("✅ CoreData CloudKit zone exists")
            } else {
                diagnosticResults.append("⚠️ CoreData CloudKit zone not found")
                syncIssuesFound.append(SyncIssue(
                    type: .zoneConfiguration,
                    description: "CoreData CloudKit zone missing",
                    severity: .warning,
                    suggestedFix: "Zone will be created on first data save"
                ))
            }
            
        } catch {
            diagnosticResults.append("❌ Failed to check zones: \(error.localizedDescription)")
            syncIssuesFound.append(SyncIssue(
                type: .zoneConfiguration,
                description: "Could not access CloudKit zones",
                severity: .warning,
                suggestedFix: "Check network connection and try again"
            ))
        }
    }
    
    private func checkSchemaConsistency() async {
        diagnosticResults.append("🔍 Checking CloudKit Schema Consistency...")
        
        let cleanupKey = CloudKitResetUtility.cleanupVersionKey
        let cleanupCompleted = UserDefaults.standard.bool(forKey: cleanupKey)
        
        if cleanupCompleted {
            diagnosticResults.append("✅ Schema cleanup v4 completed")
        } else {
            diagnosticResults.append("⚠️ Schema cleanup pending - will run on next app launch")
            syncIssuesFound.append(SyncIssue(
                type: .schemaVersion,
                description: "CloudKit schema cleanup pending",
                severity: .warning,
                suggestedFix: "Restart the app to trigger schema cleanup"
            ))
        }
    }
    
    private func checkDataConsistency() async {
        diagnosticResults.append("🔍 Checking Data Consistency...")
        
        let syncService = iCloudSyncService.shared
        
        if syncService.isSyncEnabled {
            diagnosticResults.append("✅ iCloud sync enabled in app")
        } else {
            diagnosticResults.append("❌ iCloud sync disabled in app")
            syncIssuesFound.append(SyncIssue(
                type: .dataConsistency,
                description: "iCloud sync is disabled in app settings",
                severity: .critical,
                suggestedFix: "Enable iCloud sync in app Settings"
            ))
        }
        
        if let lastSync = syncService.lastSyncDate {
            let timeSinceSync = Date().timeIntervalSince(lastSync)
            diagnosticResults.append("📅 Last sync: \(lastSync.formatted())")
            
            if timeSinceSync > 3600 { // More than 1 hour
                diagnosticResults.append("⚠️ Last sync was over 1 hour ago")
                syncIssuesFound.append(SyncIssue(
                    type: .dataConsistency,
                    description: "Last sync was \(Int(timeSinceSync/60)) minutes ago",
                    severity: .warning,
                    suggestedFix: "Try triggering manual sync"
                ))
            }
        } else {
            diagnosticResults.append("❓ No previous sync recorded")
        }
        
        switch syncService.syncStatus {
        case .idle:
            diagnosticResults.append("ℹ️ Sync status: Idle")
        case .syncing:
            diagnosticResults.append("🔄 Sync status: Currently syncing")
        case .success:
            diagnosticResults.append("✅ Sync status: Last sync successful")
        case .error(let message):
            diagnosticResults.append("❌ Sync status: Error - \(message)")
            syncIssuesFound.append(SyncIssue(
                type: .dataConsistency,
                description: "Sync error: \(message)",
                severity: .critical,
                suggestedFix: "Check network connection and try manual sync"
            ))
        }
    }
    
    private func checkKeyValueStore() async {
        diagnosticResults.append("🔍 Checking iCloud Key-Value Store...")
        
        // iCloudKeyValueStore is not @MainActor — safe to call directly.
        // Using Task.detached previously caused non-Sendable capture warnings.
        let kvDiagnostics = iCloudKeyValueStore.shared.diagnostics()
        
        diagnosticResults.append("📋 Key-Value Store Status:")
        for diagnostic in kvDiagnostics {
            diagnosticResults.append("  \(diagnostic)")
            
            if diagnostic.contains("MISMATCH") {
                syncIssuesFound.append(SyncIssue(
                    type: .dataConsistency,
                    description: "Key-value mismatch detected",
                    severity: .warning,
                    suggestedFix: "Try force sync in Settings"
                ))
            }
        }
    }
    
    func triggerManualSync() async {
        diagnosticResults.append("🔄 Triggering manual sync...")
        
        let syncService = iCloudSyncService.shared
        await syncService.forceRefreshAllData()
        
        if syncService.syncStatus == .success {
            diagnosticResults.append("✅ Manual sync completed successfully")
        } else if case .error(let message) = syncService.syncStatus {
            diagnosticResults.append("❌ Manual sync failed: \(message)")
        }
    }
    
    func forceKeyValueSync() async {
        diagnosticResults.append("🔄 Forcing Key-Value Store sync...")
        
        // iCloudKeyValueStore is not @MainActor — safe to call directly.
        iCloudKeyValueStore.shared.forceSync()
        
        diagnosticResults.append("✅ Key-Value Store force sync completed")
    }
}
