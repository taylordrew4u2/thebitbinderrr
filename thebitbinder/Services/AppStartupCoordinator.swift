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
    /// (or whenever UserDefaults doesn't already have a key for a provider).
    /// UserDefaults is always checked first by AIKeyLoader, so this is the
    /// most reliable way to ensure keys are available without Xcode target setup.
    private func seedAPIKeysIfNeeded() {
        let providers: [AIProviderType] = AIProviderType.allCases
        for provider in providers {
            // Only seed if there's no user-entered key already
            let existing = UserDefaults.standard.string(forKey: provider.userDefaultsKey)
            guard existing == nil || existing!.isEmpty else { continue }

            // Try to read from the bundled plist
            if let url = Bundle.main.url(forResource: provider.secretsPlistName, withExtension: "plist"),
               let dict = NSDictionary(contentsOf: url),
               let key = dict[provider.plistKey] as? String,
               !key.isEmpty,
               !key.hasPrefix("YOUR_") {
                UserDefaults.standard.set(key, forKey: provider.userDefaultsKey)
                print("🔑 [AppStartup] Seeded \(provider.displayName) key from plist")
            }
        }

        // Log provider readiness
        print("📥 [AppStartup] Extraction providers loaded:")
        for provider in AIProviderType.allCases {
            let key = AIKeyLoader.loadKey(for: provider)
            let status = key != nil ? "✅ ready" : "⚠️  no key"
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
        print("✅ [AppStartup] Data protection sequence completed")
        print("   - Backup service ready")
        print("   - Validation service ready")
        print("   - Migration service ready")
        
        // Brief pause to ensure all systems are ready
        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
    }
    
    /// Call this after ModelContainer is available to complete data validation and migration
    func completeDataProtectionWithContext(_ context: ModelContext) async {
        print("🔧 [AppStartup] Completing data protection with model context...")
        
        // FIRST: Clean up corrupted CloudKit records (one-time fix)
        await cleanupCorruptedCloudKitRecords()
        
        // Perform data validation
        let validation = await dataValidation.validateDataIntegrity(context: context)
        
        if validation.significantDataLoss {
            print("🚨 [AppStartup] CRITICAL: Significant data loss detected!")
            dataLossDetails = "Data validation found \(validation.issues.count) issue(s): \(validation.issues.prefix(3).joined(separator: "; ")). You can restore from a recent backup in Settings → Data Safety."
            showDataLossAlert = true
        } else if !validation.isHealthy {
            print("⚠️ [AppStartup] Data validation found minor issues")
        } else {
            print("✅ [AppStartup] Data validation passed")
        }
        
        // Auto-repair broken relationships (Joke→Folder AND RoastJoke→RoastTarget)
        if !validation.issues.isEmpty {
            let repaired = await dataValidation.repairDataIssues(context: context, issues: validation.issues)
            if !repaired.isEmpty {
                print("🔧 [AppStartup] Auto-repaired \(repaired.count) issue(s): \(repaired.joined(separator: "; "))")
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
            print("✅ [AppStartup] Migration: \(message)")
        case .warning(let message):
            print("⚠️ [AppStartup] Migration: \(message)")
        case .failure(let message):
            print("❌ [AppStartup] Migration: \(message)")
        }
    }
    
    // MARK: - CloudKit Cleanup
    
    /// One-time cleanup for corrupted CloudKit records.
    /// Fixes STRING-vs-REFERENCE mismatches on CD_folder, CD_batch, etc.
    /// by deleting the entire CloudKit zone and letting CoreData re-export.
    private func cleanupCorruptedCloudKitRecords() async {
        let key = CloudKitResetUtility.cleanupVersionKey   // "cloudkit_schema_cleanup_v2"
        
        guard !UserDefaults.standard.bool(forKey: key) else {
            print("✅ [CloudKit] Schema cleanup already completed (\(key))")
            return
        }
        
        print("🔧 [CloudKit] Running one-time schema-mismatch repair...")
        
        do {
            try await CloudKitResetUtility.repairCorruptedZone()
            // repairCorruptedZone sets the flag internally on success
            print("✅ [CloudKit] Schema cleanup completed successfully")
        } catch {
            print("⚠️ [CloudKit] Cleanup error: \(error.localizedDescription)")
            // Don't set the flag — let it retry on next launch
        }
    }
}
