import UIKit
import AVFoundation
import UserNotifications
import CloudKit
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    
    // MARK: - Background Task Identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)
    static let refreshTaskIdentifier = "The-BitBinder.thebitbinder.refresh"
    static let syncTaskIdentifier    = "The-BitBinder.thebitbinder.sync"
    
    // MARK: - Background Task Scheduling State
    private var isRefreshTaskScheduled = false
    private var isSyncTaskScheduled = false
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = MemoryManager.shared
        _ = iCloudKeyValueStore.shared
        
        // Configure audio session app-wide for both playback and recording
        configureAudioSession()
        
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        NotificationManager.shared.scheduleIfNeeded()
        
        // Required for CloudKit silent push notifications between devices
        application.registerForRemoteNotifications()
        
        // Register background tasks — must happen before app finishes launching
        registerBackgroundTasks()
        
        // Initialize iCloud Drive ubiquity container — this registers BitBinder
        // in Settings → iCloud → iCloud Drive so users can see it and toggle sync.
        // Must be called on a background thread per Apple docs.
        DispatchQueue.global(qos: .utility).async {
            if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.The-BitBinder.thebitbinder") {
                let documentsURL = containerURL.appendingPathComponent("Documents")
                if !FileManager.default.fileExists(atPath: documentsURL.path) {
                    do {
                        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
                        print("✅ [iCloud Drive] Created Documents folder at: \(documentsURL.path)")
                    } catch {
                        print("⚠️ [iCloud Drive] Could not create Documents folder: \(error)")
                    }
                }
                print("✅ [iCloud Drive] Ubiquity container initialized: \(containerURL.path)")
            } else {
                print("⚠️ [iCloud Drive] Ubiquity container not available (iCloud may be disabled)")
            }
        }
        
        // Verify iCloud account using the correct container
        Task {
            do {
                let status = try await CKContainer(identifier: "iCloud.The-BitBinder.thebitbinder").accountStatus()
                switch status {
                case .available:
                    print("✅ [CloudKit] iCloud account available — sync enabled")
                case .noAccount:
                    print("⚠️ [CloudKit] No iCloud account — sync disabled")
                case .restricted:
                    print("⚠️ [CloudKit] iCloud restricted — sync disabled")
                case .couldNotDetermine:
                    print("⚠️ [CloudKit] Could not determine iCloud status")
                case .temporarilyUnavailable:
                    print("⚠️ [CloudKit] iCloud temporarily unavailable")
                @unknown default:
                    print("⚠️ [CloudKit] Unknown iCloud status: \(status.rawValue)")
                }
            } catch {
                print("❌ [CloudKit] Error checking account: \(error)")
            }
        }
        
        return true
    }
    
    // MARK: - Remote Notification Handling (CloudKit Sync)
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ [CloudKit] Registered for remote notifications")
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("⚠️ [CloudKit] Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // THIS IS THE KEY METHOD — CloudKit sends a silent push when another device
    // writes data. We must call the completion handler with .newData so iOS knows
    // we processed it, and post the NSPersistentStoreRemoteChange notification
    // so SwiftData merges the incoming records into the local store immediately.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Let CloudKit process the notification (subscription-based record changes)
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        
        if notification?.notificationType == .recordZone ||
           notification?.notificationType == .query ||
           notification?.notificationType == .database {
            // Trigger SwiftData to merge remote changes
            NotificationCenter.default.post(
                name: .NSPersistentStoreRemoteChange,
                object: nil,
                userInfo: userInfo
            )
            print("🔄 [CloudKit] Remote notification received — merging changes")
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        MemoryManager.shared.handleMemoryWarning()
    }
    
    /// Called when the app moves to background — schedule pending background tasks.
    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleBackgroundRefresh()
        scheduleBackgroundSync()
    }
    
    // MARK: - Background Task Registration
    
    private func registerBackgroundTasks() {
        // App refresh task — lightweight periodic check (≤30s runtime)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleAppRefresh(task as! BGAppRefreshTask)
        }
        
        // Processing task — heavier iCloud sync work (minutes of runtime, requires power + network)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.syncTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundSync(task as! BGProcessingTask)
        }
        
        print("✅ [BGTask] Registered background tasks: refresh, sync")
    }
    
    // MARK: - Background Task Handlers
    
    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        let startTime = Date()
        print("🔄 [BGTask] App refresh STARTED at \(startTime.formatted(date: .omitted, time: .standard))")
        self.isRefreshTaskScheduled = false
        // Schedule the next refresh before doing work
        scheduleBackgroundRefresh()
        
        let refreshTask = Task {
            // Refresh background download status
            await MainActor.run {
                BackgroundDownloadHandler.shared.refresh()
            }
            let elapsed = Date().timeIntervalSince(startTime)
            print("🔄 [BGTask] App refresh COMPLETED in \(String(format: "%.1f", elapsed))s")
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = {
            let elapsed = Date().timeIntervalSince(startTime)
            print("⚠️ [BGTask] App refresh EXPIRED after \(String(format: "%.1f", elapsed))s — cancelling")
            refreshTask.cancel()
            self.isRefreshTaskScheduled = false
            task.setTaskCompleted(success: false)
        }
    }
    
    private func handleBackgroundSync(_ task: BGProcessingTask) {
        let startTime = Date()
        print("🔄 [BGTask] Background sync STARTED at \(startTime.formatted(date: .omitted, time: .standard))")
        self.isSyncTaskScheduled = false
        // Schedule the next sync before doing work
        scheduleBackgroundSync()
        
        let syncTask = Task {
            // Trigger iCloud sync merge
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .NSPersistentStoreRemoteChange,
                    object: nil
                )
                BackgroundDownloadHandler.shared.refresh()
            }
            
            // Allow a brief window for SwiftData to process the merge
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let elapsed = Date().timeIntervalSince(startTime)
            print("🔄 [BGTask] Background sync COMPLETED in \(String(format: "%.1f", elapsed))s")
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = {
            let elapsed = Date().timeIntervalSince(startTime)
            print("⚠️ [BGTask] Background sync EXPIRED after \(String(format: "%.1f", elapsed))s — cancelling")
            syncTask.cancel()
            self.isSyncTaskScheduled = false
            // Mark success: true since partial sync is still useful
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Background Task Scheduling
    
    private func scheduleBackgroundRefresh() {
        if isRefreshTaskScheduled {
            print("⏭️ [BGTask] Refresh already scheduled, skipping")
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
            isRefreshTaskScheduled = true
            print("📅 [BGTask] Scheduled background refresh")
        } catch {
            print("⚠️ [BGTask] Could not schedule refresh: \(error.localizedDescription)")
            isRefreshTaskScheduled = false
        }
    }
    private func scheduleBackgroundSync() {
        if isSyncTaskScheduled {
            print("⏭️ [BGTask] Sync already scheduled, skipping")
            return
        }
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        do {
            try BGTaskScheduler.shared.submit(request)
            isSyncTaskScheduled = true
            print("📅 [BGTask] Scheduled background sync")
        } catch {
            print("⚠️ [BGTask] Could not schedule sync: \(error.localizedDescription)")
            isSyncTaskScheduled = false
        }
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP,
                    .allowAirPlay,
                    .mixWithOthers
                ]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("✅ [Audio] Audio session configured for playback and recording")
        } catch {
            print("❌ [Audio] Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}
