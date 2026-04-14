import Foundation
import SwiftData

@MainActor
final class AppStartupCoordinator: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var statusText = "Loading..."
    @Published private(set) var dataProtectionStatus = ""
    /// Set to true when DataValidationService detects significant data loss.
    /// The main app view should observe this and show a recovery alert.
    @Published var showDataLossAlert = false
    /// Details of the data loss for the alert message.
    @Published var dataLossDetails: String = ""
    
    private let dataProtection = DataProtectionService.shared
    private let dataValidation = DataValidationService.shared
    private let dataMigration = DataMigrationService.shared
    private let schemaDeployment = SchemaDeploymentService.shared
    
    func start() async {
        guard !isReady else { return }

        // Seed any API keys that weren't entered via Settings UI
        seedAPIKeysIfNeeded()

        await performDataProtectionSequence()

        statusText = "Ready"
        isReady = true
    }

    // MARK: - API Key Seeding

    /// Seeds API keys from the bundled plists into UserDefaults on first launch
    /// (or whenever Keychain doesn't already have a key for a provider).
    /// Keychain is always checked first by AIKeyLoader, so this is the
    /// most reliable way to ensure keys are available without Xcode target setup.
    private func seedAPIKeysIfNeeded() {
        let providers: [AIProviderType] = AIProviderType.allCases
        for provider in providers {
            // Only seed if there's no user-entered key already
            let existing = KeychainHelper.load(forKey: provider.keychainKey)
            guard existing == nil || (existing?.isEmpty ?? true) else { continue }

            // Try to read from the bundled plist
            if let url = Bundle.main.url(forResource: provider.secretsPlistName, withExtension: "plist"),
               let dict = NSDictionary(contentsOf: url),
               let key = dict[provider.plistKey] as? String,
               !key.isEmpty,
               !key.hasPrefix("YOUR_") {
                KeychainHelper.save(key, forKey: provider.keychainKey)
                print(" [AppStartup] Seeded \(provider.displayName) key to Keychain from plist")
            }
        }

        // Log provider readiness
        print(" [AppStartup] Extraction providers loaded:")
        for provider in AIProviderType.allCases {
            let key = AIKeyLoader.loadKey(for: provider)
            let status = key != nil ? " ready" : "  no key"
            print("   \(provider.displayName): \(status)")
        }
    }

    private func performDataProtectionSequence() async {
        // Step 1: Version Check and Backup
        statusText = "Checking app version..."
        dataProtectionStatus = "Checking for updates..."
        await dataProtection.checkVersionAndBackupIfNeeded()
        
        // Step 2: Get model context for data operations
        // Note: This would need to be injected from the main app
        // For now, we'll defer the migration until we have context
        statusText = "Initializing data protection..."
        dataProtectionStatus = "Data protection services ready"
        
        // Step 3: Basic validation (without context for now)
        statusText = "Validating system..."
        
        // Log data protection readiness
        print(" [AppStartup] Data protection sequence completed")
        print("   - Backup service ready")
        print("   - Validation service ready")
        print("   - Migration service ready")
        
        // Brief hold so the launch animation is visible but doesn't feel slow.
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
    }
    
    /// Call this after ModelContainer is available to complete data validation and migration
    func completeDataProtectionWithContext(_ context: ModelContext) async {
        print(" [AppStartup] Completing data protection with model context...")
        
        // ── Post-restore confirmation ─────────────────────────────────────
        // If the user restored from a backup and the app restarted, confirm
        // the restore succeeded now that the store is loaded.
        if dataProtection.hasPendingRestoreRestart() {
            dataProtection.clearPendingRestoreRestart()
            print(" [AppStartup] Post-restore startup — data restored successfully")
            DataOperationLogger.shared.logSuccess("App restarted after backup restore — store loaded OK")
            
            // Reset validation counts since the restored store may have different
            // entity counts than the pre-restore baseline.
            UserDefaults.standard.removeObject(forKey: "DataValidation_Counts")
        }
        
        // ── Corruption cleanup detection ────────────────────────────────
        // If the ModelContainer initializer had to wipe the store and create
        // a fresh one, inform the user so they can restore from a backup.
        if UserDefaults.standard.bool(forKey: "ModelContainer_CorruptionCleanupPerformed") {
            let isInMemory = UserDefaults.standard.bool(forKey: "ModelContainer_InMemoryFallback")
            let cleanupTimestamp = UserDefaults.standard.double(forKey: "ModelContainer_CorruptionCleanupTimestamp")
            let cleanupDate = Date(timeIntervalSince1970: cleanupTimestamp)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let dateStr = formatter.string(from: cleanupDate)
            
            print(" [AppStartup] CRITICAL: Store corruption cleanup was performed at \(dateStr)")
            DataOperationLogger.shared.logCritical("Post-corruption startup detected — alerting user")
            
            if isInMemory {
                dataLossDetails = "Your data store was corrupted and could not be recovered. The app is running in temporary mode — any changes will be lost when the app closes. Please restore from a backup immediately in Settings → Data Safety."
            } else {
                dataLossDetails = "Your data store was corrupted on \(dateStr) and had to be rebuilt. A backup of the corrupted store was saved automatically. You can restore from a recent backup in Settings → Data Safety."
            }
            showDataLossAlert = true
            
            // Clear the one-shot flag so the alert only shows once
            UserDefaults.standard.removeObject(forKey: "ModelContainer_CorruptionCleanupPerformed")
            UserDefaults.standard.removeObject(forKey: "ModelContainer_InMemoryFallback")
            // Keep the timestamp for audit trail
            
            // Reset validation counts — the fresh store is empty so comparing
            // against the old baseline would falsely trigger a second "data loss" alert.
            UserDefaults.standard.removeObject(forKey: "DataValidation_Counts")
        }
        
        // NOTE: CloudKit zone cleanup (repairCorruptedZone) already runs in
        // thebitbinderApp.performAggressiveCloudKitCleanup() before this method
        // is called. No need to duplicate it here — both used the same guard key.
        
        // One-time reset: clear stale validation counts from pre-migration era.
        // After a bundle ID change, entity counts start at 0 until CloudKit syncs,
        // which falsely triggers "significant data loss" detection.
        let migrationCountsResetKey = "DataValidation_CountsReset_v10"
        if !UserDefaults.standard.bool(forKey: migrationCountsResetKey) {
            UserDefaults.standard.removeObject(forKey: "DataValidation_Counts")
            UserDefaults.standard.set(true, forKey: migrationCountsResetKey)
            print(" [AppStartup] Reset stale validation counts after bundle ID migration")
        }
        
        // Purge soft-deleted items older than 30 days before validation runs
        purgeExpiredTrashItems(context: context)

        // Perform data validation
        let validation = await dataValidation.validateDataIntegrity(context: context)
        
        if validation.significantDataLoss && !validation.issues.isEmpty {
            print(" [AppStartup] CRITICAL: Significant data loss detected!")
            dataLossDetails = "Data validation found \(validation.issues.count) issue(s): \(validation.issues.prefix(3).joined(separator: "; ")). You can restore from a recent backup in Settings  Data Safety."
            showDataLossAlert = true
        } else if validation.significantDataLoss {
            // Count dropped but no actual corruption — likely trash purge or migration.
            // Just log it, don't alarm the user.
            print(" [AppStartup] Entity count drop detected but no data issues found — likely normal (trash purge, migration)")
        } else if !validation.isHealthy {
            print(" [AppStartup] Data validation found minor issues")
        } else {
            print(" [AppStartup] Data validation passed")
        }
        
        // Auto-repair broken relationships (JokeFolder AND RoastJokeRoastTarget)
        if !validation.issues.isEmpty {
            let repaired = await dataValidation.repairDataIssues(context: context, issues: validation.issues)
            if !repaired.isEmpty {
                print(" [AppStartup] Auto-repaired \(repaired.count) issue(s): \(repaired.joined(separator: "; "))")
            }
        }
        
        // Handle schema changes
        await dataMigration.handleSchemaChanges(context: context)
        
        // Verify CloudKit schema deployment
        schemaDeployment.logSchemaFields()
        await schemaDeployment.ensureSchemaDeployed(context: context)
        
        // Perform any needed migrations
        let migrationResult = await dataMigration.performSafeMigration(context: context)
        
        switch migrationResult {
        case .success(let message):
            print(" [AppStartup] Migration: \(message)")
        case .warning(let message):
            print(" [AppStartup] Migration: \(message)")
        case .failure(let message):
            print(" [AppStartup] Migration: \(message)")
        }
    }
    
    // MARK: - Trash Auto-Purge

    /// Hard-deletes any soft-deleted records whose `deletedDate` is more than 30 days ago.
    /// Runs once per app launch, before validation, so stale trash doesn't inflate counts.
    /// Recordings: audio files are deleted before the DB record is removed.
    private func purgeExpiredTrashItems(context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let distantFuture = Date.distantFuture
        var purgeCount = 0

        // Jokes
        if let jokes = try? context.fetch(FetchDescriptor<Joke>(
            predicate: #Predicate { $0.isDeleted == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for joke in jokes { context.delete(joke) }
            purgeCount += jokes.count
        }

        // BrainstormIdeas
        if let ideas = try? context.fetch(FetchDescriptor<BrainstormIdea>(
            predicate: #Predicate { $0.isDeleted == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for idea in ideas { context.delete(idea) }
            purgeCount += ideas.count
        }

        // SetLists
        if let setLists = try? context.fetch(FetchDescriptor<SetList>(
            predicate: #Predicate { $0.isDeleted == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for setList in setLists { context.delete(setList) }
            purgeCount += setLists.count
        }

        // RoastJokes
        if let roastJokes = try? context.fetch(FetchDescriptor<RoastJoke>(
            predicate: #Predicate { $0.isDeleted == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for joke in roastJokes { context.delete(joke) }
            purgeCount += roastJokes.count
        }

        // NotebookPhotoRecords
        if let photos = try? context.fetch(FetchDescriptor<NotebookPhotoRecord>(
            predicate: #Predicate { $0.isDeleted == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for photo in photos { context.delete(photo) }
            purgeCount += photos.count
        }

        // RoastTargets — cascade deletes their RoastJokes
        if let targets = try? context.fetch(FetchDescriptor<RoastTarget>(
            predicate: #Predicate { $0.isDeleted == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for target in targets { context.delete(target) }
            purgeCount += targets.count
        }

        // JokeFolders — nullifies joke relationships on delete
        if let folders = try? context.fetch(FetchDescriptor<JokeFolder>(
            predicate: #Predicate { $0.isDeleted == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for folder in folders { context.delete(folder) }
            purgeCount += folders.count
        }

        // Recordings — delete audio file first, then DB record
        if let recordings = try? context.fetch(FetchDescriptor<Recording>(
            predicate: #Predicate { $0.isDeleted == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for recording in recordings {
                // Resolve audio file URL (handles stale absolute paths)
                let fileURL = recording.resolvedURL
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        print(" [AutoPurge] Could not delete audio file '\(fileURL.lastPathComponent)': \(error)")
                    }
                }
                context.delete(recording)
            }
            purgeCount += recordings.count
        }

        if purgeCount > 0 {
            do {
                try context.save()
                print(" [AutoPurge] Permanently deleted \(purgeCount) item(s) from trash (>30 days old)")
            } catch {
                print(" [AutoPurge] Failed to save after trash purge: \(error)")
            }
        } else {
            print(" [AutoPurge] No expired trash items found")
        }
    }

}
