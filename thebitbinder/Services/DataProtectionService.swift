//
//  DataProtectionService.swift
//  thebitbinder
//
//  Created for comprehensive data protection during app updates
//

import Foundation
import SwiftData
import CloudKit
import UIKit

/// Comprehensive data protection service to prevent data loss during app updates, migrations, and system failures
@MainActor
final class DataProtectionService: ObservableObject {
    
    static let shared = DataProtectionService()
    
    private let fileManager = FileManager.default
    private let backupDirectory: URL
    private let maxBackups = 10 // Keep maximum 10 backups
    
    // Current app version for tracking updates
    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    // Previous app version key for UserDefaults
    private let previousVersionKey = "DataProtection_PreviousAppVersion"
    private let pendingRestoreRestartKey = "DataProtection_PendingRestoreRestart"
    
    init() {
        // Create backup directory in Application Support
        self.backupDirectory = URL.applicationSupportDirectory
            .appending(path: "DataBackups", directoryHint: .isDirectory)
        
        // Ensure backup directory exists
        try? fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
        
        // Log initialization
        print(" [DataProtection] Service initialized")
        print(" [DataProtection] Backup directory: \(backupDirectory.path)")
    }
    
    // MARK: - Version Tracking
    
    /// Checks if this is a new app version and creates a backup if needed
    func checkVersionAndBackupIfNeeded() async {
        let previousVersion = UserDefaults.standard.string(forKey: previousVersionKey)
        let currentVersion = currentAppVersion
        
        print(" [DataProtection] Version check - Previous: \(previousVersion ?? "none"), Current: \(currentVersion)")
        
        if previousVersion != currentVersion {
            print(" [DataProtection] App version change detected - creating safety backup")
            await createUpdateBackup(from: previousVersion, to: currentVersion)
            
            // Update stored version
            UserDefaults.standard.set(currentVersion, forKey: previousVersionKey)
        }
    }
    
    // MARK: - Backup Creation
    
    /// Creates a complete backup of all user data before any update or migration
    func createUpdateBackup(from previousVersion: String?, to newVersion: String) async {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupName = "Update_\(previousVersion ?? "unknown")_to_\(newVersion)_\(timestamp)"
        
        await createBackup(named: backupName, reason: .appUpdate)
    }
    
    /// Creates a complete backup of all user data
    func createBackup(named name: String? = nil, reason: BackupReason = .manual) async {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupName = name ?? "Manual_\(timestamp)"
        let backupURL = backupDirectory.appending(path: backupName, directoryHint: .isDirectory)
        
        do {
            // Create backup directory
            try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
            
            print(" [DataProtection] Creating backup: \(backupName)")
            
            // Backup SwiftData store files
            let didBackupStore = await backupSwiftDataStore(to: backupURL)
            guard didBackupStore else {
                try? fileManager.removeItem(at: backupURL)
                print(" [DataProtection] Backup aborted: SwiftData store backup missing")
                return
            }
            
            // Backup UserDefaults
            backupUserDefaults(to: backupURL)
            
            // Backup app-specific files (recordings, photos, etc.)
            await backupAppSpecificFiles(to: backupURL)
            
            // Create backup manifest
            createBackupManifest(at: backupURL, reason: reason)
            
            print(" [DataProtection] Backup created successfully: \(backupName)")
            
            // Clean up old backups
            cleanupOldBackups()
            
        } catch {
            print(" [DataProtection] Failed to create backup: \(error)")
        }
    }
    
    // MARK: - Individual Backup Components
    
    private func backupSwiftDataStore(to backupURL: URL) async -> Bool {
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        let storeDirectory = backupURL.appending(path: "SwiftData", directoryHint: .isDirectory)
        
        do {
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            var copiedStoreComponent = false
            
            // Backup main store file and SQLite journal files
            for ext in ["", "-shm", "-wal"] {
                let sourceURL = URL(fileURLWithPath: storeURL.path + ext)
                let destURL = storeDirectory.appending(path: "default.store\(ext)")
                
                if fileManager.fileExists(atPath: sourceURL.path) {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                    print(" [DataProtection] Backed up: default.store\(ext)")
                    if ext.isEmpty {
                        copiedStoreComponent = true
                    }
                }
            }
            
            // Backup the external storage directory
            // SwiftData stores @Attribute(.externalStorage) blobs here (e.g. RoastTarget photos)
            let externalStorageURL = URL(fileURLWithPath: storeURL.path + "_Files")
            if fileManager.fileExists(atPath: externalStorageURL.path) {
                let destExternalURL = storeDirectory.appending(path: "default.store_Files")
                try fileManager.copyItem(at: externalStorageURL, to: destExternalURL)
                print(" [DataProtection] External storage directory backed up")
            }
            
            print(" [DataProtection] SwiftData store backed up")
            return copiedStoreComponent
        } catch {
            print(" [DataProtection] Failed to backup SwiftData store: \(error)")
            return false
        }
    }
    
    private func backupUserDefaults(to backupURL: URL) {
        let preferencesURL = backupURL.appending(path: "UserDefaults.plist")
        
        do {
            let userDefaults = UserDefaults.standard
            let dict = userDefaults.dictionaryRepresentation()
            
            // Filter out system keys and focus on app-specific data
            let appKeys = dict.keys.filter { key in
                !key.hasPrefix("NS") &&
                !key.hasPrefix("Apple") &&
                !key.hasPrefix("com.apple") &&
                !key.contains("DeviceCheck")
            }
            
            // Safely map keys to their values, filtering out any nil values
            let appDict = Dictionary(uniqueKeysWithValues: appKeys.compactMap { key -> (String, Any)? in
                guard let value = dict[key] else { return nil }
                return (key, value)
            })
            let plistData = try PropertyListSerialization.data(fromPropertyList: appDict, format: .xml, options: 0)
            try plistData.write(to: preferencesURL)
            
            print(" [DataProtection] UserDefaults backed up (\(appKeys.count) app keys)")
        } catch {
            print(" [DataProtection] Failed to backup UserDefaults: \(error)")
        }
    }
    
    private func backupAppSpecificFiles(to backupURL: URL) async {
        let appFilesURL = backupURL.appending(path: "AppFiles", directoryHint: .isDirectory)
        
        do {
            try fileManager.createDirectory(at: appFilesURL, withIntermediateDirectories: true)
            
            // Look for app-specific files (recordings, photos, etc.)
            let appSupportContents = try fileManager.contentsOfDirectory(at: URL.applicationSupportDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in appSupportContents {
                // Skip the main SwiftData files (already backed up separately),
                // our own backup directory, and emergency/corrupted backups
                // (they are already redundant copies of the store)
                let name = fileURL.lastPathComponent
                if name.contains("default.store") ||
                   name == "DataBackups" ||
                   name.hasPrefix("emergency_backup_") ||
                   name.hasPrefix("corrupted_store_backup_") {
                    continue
                }
                
                let destURL = appFilesURL.appending(path: fileURL.lastPathComponent)
                try fileManager.copyItem(at: fileURL, to: destURL)
            }
            
            print(" [DataProtection] App-specific files backed up")
        } catch {
            print(" [DataProtection] Failed to backup app files: \(error)")
        }
    }
    
    private func createBackupManifest(at backupURL: URL, reason: BackupReason) {
        let manifestURL = backupURL.appending(path: "backup_manifest.json")
        
        let manifest = BackupManifest(
            createdAt: Date(),
            appVersion: currentAppVersion,
            reason: reason.rawValue,
            deviceModel: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion
        )
        
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL)
        } catch {
            print(" [DataProtection] Failed to create manifest: \(error)")
        }
    }
    
    // MARK: - Backup Management
    
    private func cleanupOldBackups() {
        do {
            let backups = try fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.hasDirectoryPath }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2
                }
            
            // Remove excess backups
            if backups.count > maxBackups {
                let backupsToDelete = Array(backups.dropFirst(maxBackups))
                for backup in backupsToDelete {
                    try fileManager.removeItem(at: backup)
                    print(" [DataProtection] Cleaned up old backup: \(backup.lastPathComponent)")
                }
            }
        } catch {
            print(" [DataProtection] Failed to cleanup old backups: \(error)")
        }
    }
    
    // MARK: - Emergency Backup Cleanup
    
    /// Cleans up emergency_backup_*.store and corrupted_store_backup_* files/directories.
    /// Keeps only the 3 most recent *backup sets* and deletes any older than 7 days.
    /// A backup set groups the main store file with its companion files (-shm, -wal, _Files).
    /// Nonisolated because this is pure FileManager I/O — no UI state touched.
    nonisolated func cleanupEmergencyBackups() {
        let fm = FileManager.default
        let supportDir = URL.applicationSupportDirectory
        let maxEmergencyBackups = 3
        let maxAgeDays: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        let cutoffDate = Date().addingTimeInterval(-maxAgeDays)
        
        do {
            let allFiles = try fm.contentsOfDirectory(
                at: supportDir,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isDirectoryKey]
            )
            
            // Find all emergency/corrupted backup items
            let emergencyItems = allFiles.filter {
                $0.lastPathComponent.hasPrefix("emergency_backup_") ||
                $0.lastPathComponent.hasPrefix("corrupted_store_backup_")
            }
            
            guard !emergencyItems.isEmpty else { return }
            
            // Group companion files into backup sets by their base name.
            // emergency_backup_<ts>.store, .store-shm, .store-wal, .store_Files → same set
            // corrupted_store_backup_<ts>/ → already a directory, is its own set
            var backupSets: [String: [URL]] = [:]
            for item in emergencyItems {
                let name = item.lastPathComponent
                // Strip SQLite companion suffixes to find the base key
                let base: String
                if name.hasSuffix("-shm") || name.hasSuffix("-wal") {
                    base = String(name.dropLast(4)) // remove -shm / -wal
                } else if name.hasSuffix("_Files") {
                    base = String(name.dropLast(6)) // remove _Files
                } else {
                    base = name
                }
                backupSets[base, default: []].append(item)
            }
            
            // Sort sets by the creation date of the primary file (newest first)
            let sortedSets = backupSets.sorted { set1, set2 in
                let date1 = set1.value.compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }.max() ?? Date.distantPast
                let date2 = set2.value.compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }.max() ?? Date.distantPast
                return date1 > date2
            }
            
            var deletedCount = 0
            var freedBytes: Int64 = 0
            
            for (index, (_, urls)) in sortedSets.enumerated() {
                let setDate = urls.compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }.max() ?? Date.distantPast
                
                // Delete entire set if: beyond the max keep count OR older than cutoff
                if index >= maxEmergencyBackups || setDate < cutoffDate {
                    for fileURL in urls {
                        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        let size: Int64
                        if isDir {
                            var dirSize: Int64 = 0
                            if let enumerator = fm.enumerator(at: fileURL, includingPropertiesForKeys: [.fileSizeKey]) {
                                for case let child as URL in enumerator {
                                    if let s = try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                        dirSize += Int64(s)
                                    }
                                }
                            }
                            size = dirSize
                        } else {
                            size = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                        }
                        try fm.removeItem(at: fileURL)
                        freedBytes += size
                    }
                    deletedCount += 1
                }
            }
            
            if deletedCount > 0 {
                let freedMB = ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)
                print(" [DataProtection] Cleaned up \(deletedCount) emergency backup set(s), freed \(freedMB)")
            }
        } catch {
            print(" [DataProtection] Failed to cleanup emergency backups: \(error)")
        }
    }
    
    // MARK: - Data Recovery
    
    /// Lists available backups for recovery.
    /// Includes structured backups from `DataBackups/`, plus emergency and
    /// corrupted-store backups stored directly in Application Support.
    func getAvailableBackups() -> [BackupInfo] {
        var backups: [BackupInfo] = []
        
        // ── 1. Structured backups (DataBackups/) ───────────────────────
        do {
            let backupFolders = try fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.hasDirectoryPath }
            
            for folder in backupFolders {
                let manifestURL = folder.appending(path: "backup_manifest.json")
                guard isBackupRestorable(folder) else { continue }
                
                var manifest: BackupManifest?
                if fileManager.fileExists(atPath: manifestURL.path) {
                    if let data = try? Data(contentsOf: manifestURL) {
                        manifest = try? JSONDecoder().decode(BackupManifest.self, from: data)
                    }
                }
                
                let creationDate = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                
                let backupInfo = BackupInfo(
                    name: folder.lastPathComponent,
                    url: folder,
                    createdAt: manifest?.createdAt ?? creationDate,
                    appVersion: manifest?.appVersion ?? "Unknown",
                    reason: manifest?.reason ?? "Unknown",
                    size: calculateDirectorySize(folder)
                )
                
                backups.append(backupInfo)
            }
        } catch {
            print(" [DataProtection] Failed to list structured backups: \(error)")
        }
        
        // ── 2. Emergency & corrupted-store backups (Application Support/) ──
        do {
            let supportDir = URL.applicationSupportDirectory
            let allItems = try fileManager.contentsOfDirectory(
                at: supportDir,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]
            )
            
            // Group emergency_backup_* companions into sets (same logic as cleanup)
            var emergencySets: [String: [URL]] = [:]
            let emergencyItems = allItems.filter { $0.lastPathComponent.hasPrefix("emergency_backup_") }
            for item in emergencyItems {
                let name = item.lastPathComponent
                let base: String
                if name.hasSuffix("-shm") || name.hasSuffix("-wal") {
                    base = String(name.dropLast(4))
                } else if name.hasSuffix("_Files") {
                    base = String(name.dropLast(6))
                } else {
                    base = name
                }
                emergencySets[base, default: []].append(item)
            }
            
            for (baseName, urls) in emergencySets {
                // The primary file is the .store file (without companion suffix)
                let primaryURL = urls.first { $0.lastPathComponent == baseName } ?? urls[0]
                let creationDate = (try? primaryURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let totalSize = urls.reduce(Int64(0)) { sum, url in
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDir {
                        return sum + calculateDirectorySize(url)
                    }
                    return sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                
                backups.append(BackupInfo(
                    name: baseName,
                    url: primaryURL,
                    createdAt: creationDate,
                    appVersion: "Unknown",
                    reason: "emergency",
                    size: totalSize
                ))
            }
            
            // Corrupted-store backups are directories: corrupted_store_backup_<ts>/
            let corruptedDirs = allItems.filter {
                $0.lastPathComponent.hasPrefix("corrupted_store_backup_") &&
                ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            }
            for dir in corruptedDirs {
                let storeFile = dir.appending(path: "default.store")
                guard fileManager.fileExists(atPath: storeFile.path) else { continue }
                
                let creationDate = (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                
                backups.append(BackupInfo(
                    name: dir.lastPathComponent,
                    url: dir,
                    createdAt: creationDate,
                    appVersion: "Unknown",
                    reason: "corruption_recovery",
                    size: calculateDirectorySize(dir)
                ))
            }
        } catch {
            print(" [DataProtection] Failed to list emergency/corrupted backups: \(error)")
        }
        
        return backups.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Returns true if the backup is an emergency or corrupted-store backup
    /// (flat layout: store file at root, no manifest).
    private func isEmergencyOrCorruptionBackup(_ backupURL: URL) -> Bool {
        let name = backupURL.lastPathComponent
        return name.hasPrefix("emergency_backup_") || name.hasPrefix("corrupted_store_backup_")
    }
    
    private func calculateDirectorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
    
    // MARK: - Emergency Recovery
    
    /// Recovers data from a backup (use with extreme caution).
    /// Supports both structured backups (from DataBackups/) and flat-format
    /// emergency/corrupted-store backups.
    func recoverFromBackup(_ backupInfo: BackupInfo) async throws {
        print(" [DataProtection] EMERGENCY RECOVERY: Restoring from backup \(backupInfo.name)")
        guard isBackupRestorable(backupInfo.url) else {
            throw DataProtectionError.invalidBackup("This backup is incomplete and cannot be restored.")
        }
        
        // Create a backup of current state before recovery
        await createBackup(named: "PreRecovery_\(ISO8601DateFormatter().string(from: Date()))", reason: .preRecovery)
        
        if isEmergencyOrCorruptionBackup(backupInfo.url) {
            // ── Flat-format restore ─────────────────────────────────────
            try await restoreFromFlatBackup(backupInfo)
        } else {
            // ── Structured restore ──────────────────────────────────────
            let swiftDataSource = backupInfo.url.appending(path: "SwiftData")
            let userDefaultsSource = backupInfo.url.appending(path: "UserDefaults.plist")
            let appFilesSource = backupInfo.url.appending(path: "AppFiles")
            
            // Restore SwiftData
            if fileManager.fileExists(atPath: swiftDataSource.path) {
                try await restoreSwiftDataStore(from: swiftDataSource)
            }
            
            // Restore UserDefaults
            if fileManager.fileExists(atPath: userDefaultsSource.path) {
                try restoreUserDefaults(from: userDefaultsSource)
            }
            
            // Restore app files
            if fileManager.fileExists(atPath: appFilesSource.path) {
                try restoreAppFiles(from: appFilesSource)
            }
        }
        
        UserDefaults.standard.set(true, forKey: pendingRestoreRestartKey)
        print(" [DataProtection] Recovery completed from backup \(backupInfo.name)")
    }

    func hasPendingRestoreRestart() -> Bool {
        UserDefaults.standard.bool(forKey: pendingRestoreRestartKey)
    }

    func clearPendingRestoreRestart() {
        UserDefaults.standard.removeObject(forKey: pendingRestoreRestartKey)
    }

    private func isBackupRestorable(_ backupURL: URL) -> Bool {
        // Structured backup: has manifest + SwiftData/default.store
        let manifestURL = backupURL.appending(path: "backup_manifest.json")
        let swiftDataStoreURL = backupURL
            .appending(path: "SwiftData", directoryHint: .isDirectory)
            .appending(path: "default.store")
        
        if fileManager.fileExists(atPath: manifestURL.path) &&
            fileManager.fileExists(atPath: swiftDataStoreURL.path) {
            return true
        }
        
        // Flat-format: emergency backup file (the URL IS the .store file)
        let name = backupURL.lastPathComponent
        if name.hasPrefix("emergency_backup_") && name.hasSuffix(".store") {
            return fileManager.fileExists(atPath: backupURL.path)
        }
        
        // Flat-format: corrupted store backup directory (default.store at root)
        if name.hasPrefix("corrupted_store_backup_") {
            let storeFile = backupURL.appending(path: "default.store")
            return fileManager.fileExists(atPath: storeFile.path)
        }
        
        return false
    }
    
    /// Restores from a flat-format emergency or corrupted-store backup.
    /// Emergency backups: the URL points to the `.store` file; companions
    /// sit alongside it with the same base name.
    /// Corrupted backups: the URL is a directory containing `default.store`
    /// plus optional companions.
    private func restoreFromFlatBackup(_ backupInfo: BackupInfo) async throws {
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        let extensions = ["", "-shm", "-wal"]
        
        // Step 1: Remove existing store files & external storage
        for ext in extensions {
            let destFile = URL(fileURLWithPath: storeURL.path + ext)
            if fileManager.fileExists(atPath: destFile.path) {
                try fileManager.removeItem(at: destFile)
                print(" [DataProtection] Removed existing: default.store\(ext)")
            }
        }
        let externalStorageURL = URL(fileURLWithPath: storeURL.path + "_Files")
        if fileManager.fileExists(atPath: externalStorageURL.path) {
            try fileManager.removeItem(at: externalStorageURL)
            print(" [DataProtection] Removed existing external storage directory")
        }
        
        // Step 2: Determine source layout and copy files
        let name = backupInfo.url.lastPathComponent
        
        if name.hasPrefix("emergency_backup_") && name.hasSuffix(".store") {
            // Emergency backup: URL is the .store file, companions are siblings
            let basePath = backupInfo.url.path
            for ext in extensions {
                let src = URL(fileURLWithPath: basePath + ext)
                let dst = URL(fileURLWithPath: storeURL.path + ext)
                if fileManager.fileExists(atPath: src.path) {
                    try fileManager.copyItem(at: src, to: dst)
                    print(" [DataProtection] Restored: default.store\(ext) (from emergency backup)")
                }
            }
            // External storage companion
            let srcExternal = URL(fileURLWithPath: basePath + "_Files")
            if fileManager.fileExists(atPath: srcExternal.path) {
                try fileManager.copyItem(at: srcExternal, to: externalStorageURL)
                print(" [DataProtection] Restored external storage directory (from emergency backup)")
            }
        } else if name.hasPrefix("corrupted_store_backup_") {
            // Corrupted backup: URL is a directory containing default.store + companions
            for ext in extensions {
                let src = backupInfo.url.appending(path: "default.store\(ext)")
                let dst = URL(fileURLWithPath: storeURL.path + ext)
                if fileManager.fileExists(atPath: src.path) {
                    try fileManager.copyItem(at: src, to: dst)
                    print(" [DataProtection] Restored: default.store\(ext) (from corrupted backup)")
                }
            }
            let srcExternal = backupInfo.url.appending(path: "default.store_Files")
            if fileManager.fileExists(atPath: srcExternal.path) {
                try fileManager.copyItem(at: srcExternal, to: externalStorageURL)
                print(" [DataProtection] Restored external storage directory (from corrupted backup)")
            }
        }
        
        print(" [DataProtection] Flat-format store restored — app must restart to load")
    }
    
    private func restoreSwiftDataStore(from sourceURL: URL) async throws {
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        
        // All possible SQLite/SwiftData companion files
        let extensions = ["", "-shm", "-wal"]
        
        // Step 1: Remove ALL existing store files (including journal)
        // This prevents SQLite from replaying old WAL entries over restored data
        for ext in extensions {
            let destFile = URL(fileURLWithPath: storeURL.path + ext)
            if fileManager.fileExists(atPath: destFile.path) {
                try fileManager.removeItem(at: destFile)
                print(" [DataProtection] Removed existing: default.store\(ext)")
            }
        }
        
        // Also remove the SwiftData external storage directory
        // (this is where @Attribute(.externalStorage) blobs like photoData live)
        let externalStorageURL = URL(fileURLWithPath: storeURL.path + "_Files")
        if fileManager.fileExists(atPath: externalStorageURL.path) {
            try fileManager.removeItem(at: externalStorageURL)
            print(" [DataProtection] Removed existing external storage directory")
        }
        
        // Step 2: Copy backup files into place
        for ext in extensions {
            let sourceFile = sourceURL.appending(path: "default.store\(ext)")
            let destFile = URL(fileURLWithPath: storeURL.path + ext)
            
            if fileManager.fileExists(atPath: sourceFile.path) {
                try fileManager.copyItem(at: sourceFile, to: destFile)
                print(" [DataProtection] Restored: default.store\(ext)")
            }
        }
        
        // Step 3: Restore external storage directory if it was backed up
        let sourceExternalStorage = sourceURL.appending(path: "default.store_Files")
        if fileManager.fileExists(atPath: sourceExternalStorage.path) {
            try fileManager.copyItem(at: sourceExternalStorage, to: externalStorageURL)
            print(" [DataProtection] Restored external storage directory")
        }
        
        print(" [DataProtection] SwiftData store fully restored — app must restart to load")
    }
    
    private func restoreUserDefaults(from sourceURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] ?? [:]
        
        for (key, value) in dict {
            UserDefaults.standard.set(value, forKey: key)
        }
        
        UserDefaults.standard.synchronize()
    }
    
    private func restoreAppFiles(from sourceURL: URL) throws {
        let contents = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
        
        for fileURL in contents {
            let destURL = URL.applicationSupportDirectory.appending(path: fileURL.lastPathComponent)
            
            // Remove existing file/directory
            try? fileManager.removeItem(at: destURL)
            
            // Copy from backup
            try fileManager.copyItem(at: fileURL, to: destURL)
        }
    }
}

// MARK: - Supporting Types

enum BackupReason: String, Codable {
    case manual = "manual"
    case appUpdate = "app_update"
    case preRecovery = "pre_recovery"
    case scheduled = "scheduled"
    case preDataOperation = "pre_data_operation"
}

struct BackupManifest: Codable {
    let createdAt: Date
    let appVersion: String
    let reason: String
    let deviceModel: String
    let systemVersion: String
}

struct BackupInfo: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let createdAt: Date
    let appVersion: String
    let reason: String
    let size: Int64
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum DataProtectionError: LocalizedError {
    case invalidBackup(String)

    var errorDescription: String? {
        switch self {
        case .invalidBackup(let message):
            return message
        }
    }
}
