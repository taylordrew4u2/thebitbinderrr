import UIKit
import AVFoundation
import UserNotifications
import CloudKit
import BackgroundTasks

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    
    // MARK: - Background Task Identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)
    static let refreshTaskIdentifier = "The-BitBinder.thebitbinder.refresh"
    static let syncTaskIdentifier    = "The-BitBinder.thebitbinder.sync"
    
    // MARK: - Background Task Scheduling State
    // The whole class is @MainActor — UIKit always calls delegate methods on
    // the main thread, and making the class @MainActor ensures the Swift
    // concurrency runtime recognises the correct isolation context. BGTask
    // handler closures run on background queues and must hop to MainActor
    // (via Task { @MainActor }) before touching any instance state.
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
        // in Settings  iCloud  iCloud Drive so users can see it and toggle sync.
        // Must be called on a background thread per Apple docs.
        DispatchQueue.global(qos: .utility).async {
            if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.The-BitBinder.thebitbinder") {
                let documentsURL = containerURL.appendingPathComponent("Documents")
                if !FileManager.default.fileExists(atPath: documentsURL.path) {
                    do {
                        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
                        print(" [iCloud Drive] Created Documents folder at: \(documentsURL.path)")
                    } catch {
                        print(" [iCloud Drive] Could not create Documents folder: \(error)")
                    }
                }
                print(" [iCloud Drive] Ubiquity container initialized: \(containerURL.path)")
            } else {
                print(" [iCloud Drive] Ubiquity container not available (iCloud may be disabled)")
            }
        }
        
        // Verify iCloud account using the correct container
        Task {
            do {
                let status = try await CKContainer(identifier: "iCloud.The-BitBinder.thebitbinder").accountStatus()
                switch status {
                case .available:
                    print(" [CloudKit] iCloud account available — sync enabled")
                case .noAccount:
                    print(" [CloudKit] No iCloud account — sync disabled")
                case .restricted:
                    print(" [CloudKit] iCloud restricted — sync disabled")
                case .couldNotDetermine:
                    print(" [CloudKit] Could not determine iCloud status")
                case .temporarilyUnavailable:
                    print(" [CloudKit] iCloud temporarily unavailable")
                @unknown default:
                    print(" [CloudKit] Unknown iCloud status: \(status.rawValue)")
                }
            } catch {
                print(" [CloudKit] Error checking account: \(error)")
            }
        }
        
        return true
    }
    
    // MARK: - Remote Notification Handling (CloudKit Sync)
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print(" [CloudKit] Registered for remote notifications")
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print(" [CloudKit] Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // THIS IS THE KEY METHOD — CloudKit sends a silent push when another device
    // writes data. We must call the completion handler with .newData so iOS knows
    // we processed it, and post the NSPersistentStoreRemoteChange notification
    // so SwiftData merges the incoming records into the local store immediately.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        print(" [CloudKit] Remote notification received: \(userInfo)")
        
        // Let CloudKit process the notification (subscription-based record changes)
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        
        guard let ckNotification = notification else {
            print(" [CloudKit] Could not create CKNotification from userInfo")
            completionHandler(.noData)
            return
        }
        
        print(" [CloudKit] Notification type: \(ckNotification.notificationType.rawValue)")
        
        switch ckNotification.notificationType {
        case .recordZone, .query, .database:
            // This is a CloudKit data change notification
            print(" [CloudKit] CloudKit data change notification - triggering merge")
            
            // Post notification to trigger iCloudSyncService remote change handler.
            // The handler debounces into processRemoteChangeAsync() which refreshes
            // the SwiftData context. No additional syncNow() needed — that would
            // cascade into a second full sync via performFullSync().
            NotificationCenter.default.post(
                name: .NSPersistentStoreRemoteChange,
                object: nil,
                userInfo: userInfo
            )
            
            completionHandler(.newData)
            
        default:
            print(" [CloudKit] Non-data notification type, ignoring")
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
        // App refresh task — lightweight periodic check (30s runtime)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // Hop to MainActor to avoid unsafeForcedSync from concurrent context
            Task { @MainActor [weak self] in
                self?.handleAppRefresh(refreshTask)
            }
        }
        
        // Processing task — heavier iCloud sync work (minutes of runtime, requires power + network)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.syncTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // Hop to MainActor to avoid unsafeForcedSync from concurrent context
            Task { @MainActor [weak self] in
                self?.handleBackgroundSync(processingTask)
            }
        }
        
        print(" [BGTask] Registered background tasks: refresh, sync")
    }
    
    // MARK: - Background Task Handlers
    
    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        let startTime = Date()
        print(" [BGTask] App refresh STARTED at \(startTime.formatted(date: .omitted, time: .standard))")
        self.isRefreshTaskScheduled = false
        // Schedule the next refresh before doing work
        scheduleBackgroundRefresh()
        
        let refreshTask = Task {
            // Refresh background download status
            // Task inherits @MainActor from handleAppRefresh — no hop needed.
            BackgroundDownloadScheduler.shared.refresh()
            let elapsed = Date().timeIntervalSince(startTime)
            print(" [BGTask] App refresh COMPLETED in \(String(format: "%.1f", elapsed))s")
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = { [weak self] in
            let elapsed = Date().timeIntervalSince(startTime)
            print(" [BGTask] App refresh EXPIRED after \(String(format: "%.1f", elapsed))s — cancelling")
            refreshTask.cancel()
            Task { @MainActor [weak self] in
                self?.isRefreshTaskScheduled = false
            }
            task.setTaskCompleted(success: false)
        }
    }
    
    private func handleBackgroundSync(_ task: BGProcessingTask) {
        let startTime = Date()
        print(" [BGTask] Background sync STARTED at \(startTime.formatted(date: .omitted, time: .standard))")
        self.isSyncTaskScheduled = false
        // Schedule the next sync before doing work
        scheduleBackgroundSync()
        
        let syncTask = Task {
            // Refresh background download status. SwiftData + CloudKit will
            // automatically process any pending remote changes when the
            // persistent store coordinator runs its history processing.
            // Do NOT manually post .NSPersistentStoreRemoteChange — that
            // cascades into handleRemoteChange and triggers a redundant sync cycle.
            // Task inherits @MainActor from handleBackgroundSync — no hop needed.
            BackgroundDownloadScheduler.shared.refresh()
            
            // Allow a brief window for SwiftData to process any pending merges
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let elapsed = Date().timeIntervalSince(startTime)
            print(" [BGTask] Background sync COMPLETED in \(String(format: "%.1f", elapsed))s")
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = { [weak self] in
            let elapsed = Date().timeIntervalSince(startTime)
            print(" [BGTask] Background sync EXPIRED after \(String(format: "%.1f", elapsed))s — cancelling")
            syncTask.cancel()
            Task { @MainActor [weak self] in
                self?.isSyncTaskScheduled = false
            }
            // Mark success: true since partial sync is still useful
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Background Task Scheduling
    
    private func scheduleBackgroundRefresh() {
        if isRefreshTaskScheduled {
            print(" [BGTask] Refresh already scheduled, skipping")
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        do {
            // BGTaskScheduler.submit replaces any existing pending request with the
            // same identifier, so this is already idempotent. The flag prevents
            // unnecessary submit calls.
            try BGTaskScheduler.shared.submit(request)
            isRefreshTaskScheduled = true
            print(" [BGTask] Scheduled background refresh")
        } catch let e as NSError where e.domain == "BGTaskSchedulerErrorDomain" && e.code == 3 {
            // BGTaskSchedulerErrorCodeTooManyPendingTaskRequests — already submitted
            isRefreshTaskScheduled = true
            print(" [BGTask] Refresh task already pending (too many requests)")
        } catch {
            print(" [BGTask] Could not schedule refresh: \(error.localizedDescription)")
            isRefreshTaskScheduled = false
        }
    }
    private func scheduleBackgroundSync() {
        if isSyncTaskScheduled {
            print(" [BGTask] Sync already scheduled, skipping")
            return
        }
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        do {
            try BGTaskScheduler.shared.submit(request)
            isSyncTaskScheduled = true
            print(" [BGTask] Scheduled background sync")
        } catch let e as NSError where e.domain == "BGTaskSchedulerErrorDomain" && e.code == 3 {
            // Already submitted
            isSyncTaskScheduled = true
            print(" [BGTask] Sync task already pending (too many requests)")
        } catch {
            print(" [BGTask] Could not schedule sync: \(error.localizedDescription)")
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
            print(" [Audio] Audio session configured for playback and recording")
        } catch {
            print(" [Audio] Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}
