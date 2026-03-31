//
//  MemoryManager.swift
//  thebitbinder
//
//  Memory management utility for the app
//

import UIKit
import Foundation

/// Centralized memory management for the app
final class MemoryManager {
    static let shared = MemoryManager()
    
    /// Track if we're currently clearing caches to avoid duplicate work
    private var isClearing = false
    private let clearingLock = NSLock()
    
    /// Observers for cleanup
    private var memoryWarningObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    
    private init() {
        setupObservers()
    }
    
    deinit {
        removeObservers()
    }
    
    private func setupObservers() {
        // Memory warning - highest priority
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        
        // Background transition - clear caches to reduce footprint
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleBackgroundTransition()
        }
        
        // Foreground transition - good time to report memory state
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleForegroundTransition()
        }
    }
    
    private func removeObservers() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Called when system sends memory warning
    func handleMemoryWarning() {
        // Prevent duplicate clearing
        clearingLock.lock()
        guard !isClearing else {
            clearingLock.unlock()
            return
        }
        isClearing = true
        clearingLock.unlock()
        
        print("⚠️ [MemoryManager] Memory warning received - clearing caches")
        
        // Clear caches on main thread
        DispatchQueue.main.async { [weak self] in
            // Clear URL caches
            URLCache.shared.removeAllCachedResponses()
            
            // Clear any system image caches by evicting all objects
            // from Foundation's shared caches
            URLCache.shared.memoryCapacity = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Restore a small capacity after clearing
                URLCache.shared.memoryCapacity = 4 * 1024 * 1024 // 4 MB
            }
            
            // Notify listeners (SpeechRecognizer, import pipeline, etc.)
            NotificationCenter.default.post(name: .appMemoryWarning, object: nil)
            
            #if DEBUG
            self?.reportMemoryUsage()
            #endif
            
            print("✅ [MemoryManager] Caches cleared")
            
            self?.clearingLock.lock()
            self?.isClearing = false
            self?.clearingLock.unlock()
        }
    }
    
    /// Called when app enters background
    func handleBackgroundTransition() {
        print("📱 [MemoryManager] App entering background - reducing memory footprint")
        
        // Clear URL caches
        URLCache.shared.removeAllCachedResponses()
    }
    
    /// Called when app enters foreground
    private func handleForegroundTransition() {
        #if DEBUG
        reportMemoryUsage()
        #endif
    }
    
    /// Call this to proactively reduce memory usage
    func reduceMemoryUsage() {
        handleMemoryWarning()
    }
    
    /// Report current memory usage (for debugging)
    func reportMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            print("📊 [MemoryManager] Memory usage: \(String(format: "%.1f", usedMB)) MB")
        }
    }
    
    /// Check if memory pressure is high (useful for deciding whether to load large assets)
    func isMemoryPressureHigh() -> Bool {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            // Consider memory pressure high if using more than 200MB
            return usedMB > 200
        }
        return false
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appMemoryWarning = Notification.Name("appMemoryWarning")
}
