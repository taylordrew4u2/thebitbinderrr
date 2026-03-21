//
//  DataOperationLogger.swift
//  thebitbinder
//
//  Created for comprehensive logging of data operations
//

import Foundation
import SwiftData
import OSLog

/// Comprehensive logging service for all data operations to aid in debugging data loss issues
final class DataOperationLogger {
    
    static let shared = DataOperationLogger()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.thebitbinder", category: "DataOperations")
    private let logFileURL: URL
    private let maxLogFileSize: Int = 10 * 1024 * 1024 // 10MB
    private let maxLogFiles = 5
    
    init() {
        // Create log file in Application Support
        self.logFileURL = URL.applicationSupportDirectory
            .appending(path: "DataOperations.log")
        
        // Ensure log directory exists
        try? FileManager.default.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        logOperation(.info, "DataOperationLogger initialized")
    }
    
    // MARK: - Public Logging Interface
    
    func logDataCreation<T: PersistentModel>(_ entity: T, context: ModelContext) {
        let entityName = String(describing: type(of: entity))
        let message = "CREATED \(entityName)"
        logOperation(.info, message)
        
        // Log to system logger as well
        logger.info("📝 \(message)")
    }
    
    func logDataUpdate<T: PersistentModel>(_ entity: T, context: ModelContext, changes: [String] = []) {
        let entityName = String(describing: type(of: entity))
        let changesStr = changes.isEmpty ? "" : " (changes: \(changes.joined(separator: ", ")))"
        let message = "UPDATED \(entityName)\(changesStr)"
        logOperation(.info, message)
        
        logger.info("✏️ \(message)")
    }
    
    func logDataDeletion<T: PersistentModel>(_ entity: T, context: ModelContext, soft: Bool = false) {
        let entityName = String(describing: type(of: entity))
        let deleteType = soft ? "SOFT_DELETED" : "HARD_DELETED"
        let message = "\(deleteType) \(entityName)"
        logOperation(.warning, message)
        
        logger.notice("🗑️ \(message)")
    }
    
    func logBulkOperation(_ operation: String, entityType: String, count: Int, context: ModelContext) {
        let message = "BULK_\(operation.uppercased()) \(count) \(entityType) entities"
        logOperation(.notice, message)
        
        logger.notice("📊 \(message)")
    }
    
    func logMigration(_ fromVersion: Int?, _ toVersion: Int, result: String) {
        let message = "MIGRATION from v\(fromVersion ?? 0) to v\(toVersion): \(result)"
        logOperation(.critical, message)
        
        logger.critical("🔄 \(message)")
    }
    
    func logBackup(_ backupName: String, reason: String, success: Bool) {
        let status = success ? "SUCCESS" : "FAILED"
        let message = "BACKUP \(status): \(backupName) (reason: \(reason))"
        logOperation(success ? .notice : .error, message)
        
        if success {
            logger.notice("💾 \(message)")
        } else {
            logger.error("❌ \(message)")
        }
    }
    
    func logDataValidation(_ result: DataValidationResult) {
        let message = "VALIDATION: \(result.totalEntities) entities, \(result.issues.count) issues, healthy: \(result.isHealthy)"
        logOperation(result.isHealthy ? .info : .error, message)
        
        if result.isHealthy {
            logger.info("✅ \(message)")
        } else {
            logger.error("⚠️ \(message)")
            
            // Log individual issues
            for issue in result.issues {
                logOperation(.error, "VALIDATION_ISSUE: \(issue)")
                logger.error("   - \(issue)")
            }
        }
        
        if result.significantDataLoss {
            let lossMessage = "SIGNIFICANT_DATA_LOSS_DETECTED"
            logOperation(.critical, lossMessage)
            logger.critical("🚨 \(lossMessage)")
        }
    }
    
    func logError(_ error: Error, operation: String, context: String? = nil) {
        let contextStr = context.map { " (\($0))" } ?? ""
        let message = "ERROR in \(operation)\(contextStr): \(error.localizedDescription)"
        logOperation(.error, message)
        
        logger.error("❌ \(message)")
    }
    
    func logCritical(_ message: String) {
        logOperation(.critical, "CRITICAL: \(message)")
        logger.critical("🚨 CRITICAL: \(message)")
    }
    
    // MARK: - Internal Logging
    
    func logOperation(_ level: LogLevel, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
        
        // Write to file
        writeToLogFile(logLine)
        
        // Also print to console in debug builds
        #if DEBUG
        print("🗂️ [DataLog] \(logLine.trimmingCharacters(in: .newlines))")
        #endif
    }
    
    private func writeToLogFile(_ logLine: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check if we need to rotate the log file
                if self.shouldRotateLogFile() {
                    self.rotateLogFile()
                }
                
                // Append to current log file
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    let fileHandle = try FileHandle(forWritingTo: self.logFileURL)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logLine.data(using: .utf8) ?? Data())
                    fileHandle.closeFile()
                } else {
                    try logLine.write(to: self.logFileURL, atomically: true, encoding: .utf8)
                }
                
            } catch {
                print("Failed to write to log file: \(error)")
            }
        }
    }
    
    private func shouldRotateLogFile() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? Int else {
            return false
        }
        return fileSize > maxLogFileSize
    }
    
    private func rotateLogFile() {
        do {
            // Move current log to rotated log
            let rotatedURL = logFileURL.appendingPathExtension("1")
            
            // Remove oldest rotated logs
            for i in stride(from: maxLogFiles, through: 2, by: -1) {
                let oldURL = logFileURL.appendingPathExtension("\(i)")
                let newURL = logFileURL.appendingPathExtension("\(i + 1)")
                
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    if i == maxLogFiles {
                        try FileManager.default.removeItem(at: oldURL)
                    } else {
                        try FileManager.default.moveItem(at: oldURL, to: newURL)
                    }
                }
            }
            
            // Move current to .1
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                try FileManager.default.moveItem(at: logFileURL, to: rotatedURL)
            }
            
        } catch {
            print("Failed to rotate log file: \(error)")
        }
    }
    
    // MARK: - Log Retrieval
    
    /// Gets the current log content for debugging or support
    func getCurrentLog() -> String? {
        return try? String(contentsOf: logFileURL)
    }
    
    /// Gets all log files for comprehensive debugging
    func getAllLogs() -> [String] {
        var logs: [String] = []
        
        // Add main log
        if let mainLog = getCurrentLog() {
            logs.append(mainLog)
        }
        
        // Add rotated logs
        for i in 1...maxLogFiles {
            let rotatedURL = logFileURL.appendingPathExtension("\(i)")
            if let rotatedLog = try? String(contentsOf: rotatedURL) {
                logs.append(rotatedLog)
            }
        }
        
        return logs
    }
    
    /// Exports all logs to a single file for support/debugging
    func exportLogs() -> URL? {
        let exportURL = URL.temporaryDirectory
            .appending(path: "BitBinder_DataLogs_\(ISO8601DateFormatter().string(from: Date())).txt")
        
        do {
            let allLogs = getAllLogs().joined(separator: "\n--- LOG ROTATION ---\n")
            try allLogs.write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            print("Failed to export logs: \(error)")
            return nil
        }
    }
}

// MARK: - Supporting Types

enum LogLevel: String, CaseIterable {
    case info = "INFO"
    case notice = "NOTICE"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
}

// MARK: - SwiftData Extensions for Automatic Logging

extension ModelContext {
    
    /// Enhanced save with automatic logging
    func saveWithLogging() throws {
        let logger = DataOperationLogger.shared
        
        // Log the save operation
        logger.logInfo("CONTEXT_SAVE initiated")
        
        do {
            try self.save()
            logger.logInfo("CONTEXT_SAVE completed successfully")
        } catch {
            logger.logError(error, operation: "CONTEXT_SAVE")
            throw error
        }
    }
}

// Extension for public access to logging methods
extension DataOperationLogger {
    func logInfo(_ message: String) {
        logOperation(.info, message)
    }
}
