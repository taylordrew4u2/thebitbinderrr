//
//  DataMigrationService.swift
//  thebitbinder
//
//  Created for safe data migration handling during app updates
//

import Foundation
import SwiftData

/// Service to handle data migrations safely with automatic rollback capabilities
@MainActor
final class DataMigrationService: ObservableObject {
    
    static let shared = DataMigrationService()
    
    private let migrationVersionKey = "DataMigration_LastVersion"
    private let dataProtection = DataProtectionService.shared
    private let dataValidation = DataValidationService.shared
    
    // Current migration version (increment when adding new migrations)
    private let currentMigrationVersion = 1
    
    init() {
        print("🔄 [DataMigration] Service initialized")
    }
    
    // MARK: - Migration Management
    
    /// Performs safe migration with automatic backup and rollback
    func performSafeMigration(context: ModelContext) async -> MigrationResult {
        print("🔄 [DataMigration] Starting safe migration process...")
        
        let lastMigrationVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        
        guard lastMigrationVersion < currentMigrationVersion else {
            print("🔄 [DataMigration] No migration needed")
            return .success("No migration required")
        }
        
        // Step 1: Create pre-migration backup
        print("🔄 [DataMigration] Creating pre-migration backup...")
        await dataProtection.createBackup(
            named: "PreMigration_v\(lastMigrationVersion)_to_v\(currentMigrationVersion)_\(ISO8601DateFormatter().string(from: Date()))",
            reason: .preDataOperation
        )
        
        // Step 2: Validate data integrity before migration
        print("🔄 [DataMigration] Validating data integrity...")
        let preValidation = await dataValidation.validateDataIntegrity(context: context)
        
        if preValidation.significantDataLoss {
            print("🚨 [DataMigration] Pre-migration validation failed - aborting")
            return .failure("Data integrity issues detected before migration")
        }
        
        // Step 3: Perform migrations
        var migrationResult: MigrationResult = .success("Migration completed successfully")
        
        for version in (lastMigrationVersion + 1)...currentMigrationVersion {
            print("🔄 [DataMigration] Running migration to version \(version)...")
            
            do {
                try await runMigration(toVersion: version, context: context)
                
                // Validate after each migration step
                let validation = await dataValidation.validateDataIntegrity(context: context)
                
                if !validation.isHealthy {
                    print("❌ [DataMigration] Migration to v\(version) caused data issues")
                    migrationResult = .failure("Migration to version \(version) failed validation")
                    break
                }
                
                print("✅ [DataMigration] Migration to v\(version) completed successfully")
                
            } catch {
                print("❌ [DataMigration] Migration to v\(version) failed: \(error)")
                migrationResult = .failure("Migration to version \(version) failed: \(error.localizedDescription)")
                break
            }
        }
        
        // Step 4: Handle migration result
        switch migrationResult {
        case .success:
            // Update migration version
            UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
            
            // Final validation
            let finalValidation = await dataValidation.validateDataIntegrity(context: context)
            if !finalValidation.isHealthy {
                print("⚠️ [DataMigration] Final validation found issues, but migration completed")
                return .warning("Migration completed but data validation found minor issues")
            }
            
            print("✅ [DataMigration] All migrations completed successfully")
            return migrationResult
            
        case .failure, .warning:
            // Rollback on failure
            print("🔄 [DataMigration] Migration failed, attempting rollback...")
            let rollbackResult = await performRollback(to: lastMigrationVersion)
            
            if case .success = rollbackResult {
                return .failure("Migration failed but data was successfully rolled back")
            } else {
                return .failure("Migration failed and rollback also failed - manual recovery may be needed")
            }
        }
    }
    
    // MARK: - Individual Migrations
    
    private func runMigration(toVersion version: Int, context: ModelContext) async throws {
        switch version {
        case 1:
            try await migration_v1(context: context)
        default:
            print("⚠️ [DataMigration] Unknown migration version: \(version)")
        }
    }
    
    /// Example migration v1: Add any necessary data transformations
    private func migration_v1(context: ModelContext) async throws {
        print("🔄 [DataMigration] Running migration v1...")
        
        // Example: Update any data structures that changed
        // This is where you would add specific migration logic
        
        // For now, this is a placeholder that ensures existing data is preserved
        let jokes = try context.fetch(FetchDescriptor<Joke>())
        print("🔄 [DataMigration] Validated \(jokes.count) jokes during v1 migration")
        
        // Save any changes
        try context.save()
    }
    
    // MARK: - Rollback Capabilities
    
    /// Restores the most recent pre-migration backup and resets the migration
    /// version to `targetVersion` (the version the user was on *before* the
    /// migration attempt started).
    private func performRollback(to targetVersion: Int) async -> MigrationResult {
        print("🔄 [DataMigration] Performing rollback to v\(targetVersion)...")
        
        // Get the most recent pre-migration backup
        let backups = dataProtection.getAvailableBackups()
        
        guard let preMigrationBackup = backups.first(where: { $0.name.contains("PreMigration") }) else {
            print("❌ [DataMigration] No pre-migration backup found for rollback")
            return .failure("No pre-migration backup available")
        }
        
        do {
            try await dataProtection.recoverFromBackup(preMigrationBackup)
            
            // Reset migration version to the pre-migration state
            UserDefaults.standard.set(targetVersion, forKey: migrationVersionKey)
            
            print("✅ [DataMigration] Rollback completed successfully")
            return .success("Data rolled back to pre-migration state")
            
        } catch {
            print("❌ [DataMigration] Rollback failed: \(error)")
            return .failure("Rollback failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Schema Version Management
    
    /// Checks if the app schema has changed and creates a backup if needed
    func handleSchemaChanges(context: ModelContext) async {
        let currentSchemaHash = calculateSchemaHash()
        let lastSchemaHash = UserDefaults.standard.string(forKey: "DataMigration_LastSchemaHash")
        
        if lastSchemaHash != nil && lastSchemaHash != currentSchemaHash {
            print("🔄 [DataMigration] Schema change detected, creating safety backup...")
            await dataProtection.createBackup(
                named: "SchemaChange_\(ISO8601DateFormatter().string(from: Date()))",
                reason: .preDataOperation
            )
        }
        
        UserDefaults.standard.set(currentSchemaHash, forKey: "DataMigration_LastSchemaHash")
    }
    
    private func calculateSchemaHash() -> String {
        // Create a hash of the current schema that changes when fields are
        // added, removed, or renamed — not just when entity names change.
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
        
        // Include entity names AND their property names so adding/removing
        // a field produces a different hash.
        let entityDescriptions = schema.entities.sorted { $0.name < $1.name }.map { entity in
            let props = entity.properties.map(\.name).sorted().joined(separator: ",")
            return "\(entity.name):\(props)"
        }
        let fingerprint = entityDescriptions.joined(separator: "|")
        return fingerprint.data(using: .utf8)?.base64EncodedString() ?? ""
    }
    
    // MARK: - Recovery Functions
    
    /// Attempts to recover from catastrophic data loss
    func emergencyDataRecovery() async -> MigrationResult {
        print("🚨 [DataMigration] EMERGENCY DATA RECOVERY INITIATED")
        
        // Try to find any available backup
        let backups = dataProtection.getAvailableBackups().sorted { $0.createdAt > $1.createdAt }
        
        guard let mostRecentBackup = backups.first else {
            return .failure("No backups available for emergency recovery")
        }
        
        do {
            print("🚨 [DataMigration] Attempting emergency recovery from backup: \(mostRecentBackup.name)")
            try await dataProtection.recoverFromBackup(mostRecentBackup)
            
            return .success("Emergency recovery completed from backup: \(mostRecentBackup.name)")
            
        } catch {
            print("❌ [DataMigration] Emergency recovery failed: \(error)")
            return .failure("Emergency recovery failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Status and Reporting
    
    func getMigrationStatus() -> MigrationStatus {
        let lastMigrationVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        let availableBackups = dataProtection.getAvailableBackups()
        
        return MigrationStatus(
            currentVersion: currentMigrationVersion,
            lastMigrationVersion: lastMigrationVersion,
            migrationNeeded: lastMigrationVersion < currentMigrationVersion,
            availableBackups: availableBackups.count,
            lastBackupDate: availableBackups.first?.createdAt
        )
    }
}

// MARK: - Supporting Types

enum MigrationResult {
    case success(String)
    case warning(String)
    case failure(String)
    
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .warning, .failure: return false
        }
    }
    
    var message: String {
        switch self {
        case .success(let msg), .warning(let msg), .failure(let msg):
            return msg
        }
    }
}

struct MigrationStatus {
    let currentVersion: Int
    let lastMigrationVersion: Int
    let migrationNeeded: Bool
    let availableBackups: Int
    let lastBackupDate: Date?
}
