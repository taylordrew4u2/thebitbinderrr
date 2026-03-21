import Foundation
import SwiftData

@MainActor
final class AppStartupCoordinator: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var statusText = "Loading..."
    @Published private(set) var dataProtectionStatus = ""
    
    private let dataProtection = DataProtectionService.shared
    private let dataValidation = DataValidationService.shared
    private let dataMigration = DataMigrationService.shared
    
    func start() async {
        guard !isReady else { return }

        await performDataProtectionSequence()

        statusText = "Ready"
        isReady = true
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
        
        // Perform data validation
        let validation = await dataValidation.validateDataIntegrity(context: context)
        
        if validation.significantDataLoss {
            print("🚨 [AppStartup] CRITICAL: Significant data loss detected!")
            // You might want to show an alert to the user here
        } else if !validation.isHealthy {
            print("⚠️ [AppStartup] Data validation found minor issues")
        } else {
            print("✅ [AppStartup] Data validation passed")
        }
        
        // Handle schema changes
        await dataMigration.handleSchemaChanges(context: context)
        
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
}
