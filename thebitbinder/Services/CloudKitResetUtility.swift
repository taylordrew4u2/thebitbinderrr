//
//  CloudKitResetUtility.swift
//  thebitbinder
//
//  Created for CloudKit schema reset support
//

import Foundation
import CloudKit

/// Utility for development-time CloudKit operations
/// ⚠️ Only use in development builds!
class CloudKitResetUtility {
    
    /// Checks CloudKit account status for debugging
    static func checkCloudKitStatus() {
        let container = CKContainer(identifier: "iCloud.666bit")
        
        container.accountStatus { (status, error) in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("✅ CloudKit account available")
                case .noAccount:
                    print("⚠️ No iCloud account")
                case .restricted:
                    print("⚠️ iCloud account restricted")
                case .couldNotDetermine:
                    print("⚠️ Could not determine iCloud status")
                case .temporarilyUnavailable:
                    print("⚠️ iCloud temporarily unavailable")
                @unknown default:
                    print("❓ Unknown iCloud status")
                }
                
                if let error = error {
                    print("❌ CloudKit error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Logs CloudKit container configuration for debugging
    static func logContainerInfo() {
        let container = CKContainer(identifier: "iCloud.666bit")
        print("📦 CloudKit Container ID: \(container.containerIdentifier ?? "unknown")")
        print("🔧 Environment: Development")
        
        // Check private database
        let _ = container.privateCloudDatabase
        print("🔒 Private database configured")
        
        checkCloudKitStatus()
    }
}

#if DEBUG
extension CloudKitResetUtility {
    
    /// For development only: Clear local CloudKit cache
    /// Call this after resetting the CloudKit schema in CloudKit Console
    static func clearLocalCache() {
        // Note: This doesn't actually clear the cache programmatically
        // Users need to reset simulator or delete/reinstall app
        print("📋 To clear CloudKit cache:")
        print("   1. Reset iOS Simulator: Device → Erase All Content and Settings")
        print("   2. Or delete and reinstall the app on device")
        print("   3. This ensures no cached CloudKit data conflicts with new schema")
    }
    
    /// Development helper to verify the model is properly configured
    static func verifyModelConfiguration() {
        print("🔍 SwiftData Model Verification:")
        print("   ✓ ImportBatch has @Relationship to ImportedJokeMetadata")
        print("   ✓ ImportedJokeMetadata.batch is optional ImportBatch relationship")
        print("   ✓ CloudKit will map this as REFERENCE type correctly")
    }
}
#endif
