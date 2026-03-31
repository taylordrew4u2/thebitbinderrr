//
//  BackgroundDownloadScheduler.swift
//  thebitbinder
//
//  Created by Taylor Drew on 3/19/26.
//
//  Main app helper to schedule background downloads and check status
//  from the background asset downloader extension (bit).
//

import Foundation
import BackgroundAssets
import os.log

/// Schedules background downloads and reads status written by the `bit` extension
/// via shared app group storage.
@MainActor
final class BackgroundDownloadScheduler: ObservableObject {
    
    static let shared = BackgroundDownloadScheduler()
    
    private let logger = Logger(subsystem: "The-BitBinder.thebitbinder", category: "BackgroundDownload")
    
    /// Shared app group identifier — must match the extension.
    private let appGroupIdentifier = "group.The-BitBinder.thebitbinder"
    
    // MARK: - Published State
    
    /// The last time the background extension successfully downloaded an asset.
    @Published private(set) var lastDownloadDate: Date?
    
    /// Total number of assets downloaded by the extension.
    @Published private(set) var downloadedAssetCount: Int = 0
    
    /// Last error reported by the background extension, if any.
    @Published private(set) var lastError: String?
    
    /// Currently pending download identifiers.
    @Published private(set) var pendingDownloads: [String] = []
    
    // MARK: - Init
    
    private init() {
        refresh()
    }
    
    // MARK: - Schedule Downloads
    
    /// Schedules a background URL download that the `bit` extension will handle.
    /// - Parameters:
    ///   - url: The URL to download from.
    ///   - identifier: A unique identifier for this download (e.g. "content-update-v2").
    ///   - essential: If `true`, the download must complete before the app launches
    ///                (use sparingly — only for critical assets on first install/update).
    func scheduleDownload(from url: URL, identifier: String, essential: Bool = false) throws {
        let download = BAURLDownload(
            identifier: identifier,
            request: URLRequest(url: url),
            essential: essential,
            fileSize: 0,  // 0 = unknown size; system will determine
            applicationGroupIdentifier: appGroupIdentifier,
            priority: essential ? .max : .default
        )
        
        try BADownloadManager.shared.scheduleDownload(download)
        
        // Track in shared defaults so the extension knows what's pending
        var pending = sharedDefaults?.stringArray(forKey: "pendingBackgroundDownloads") ?? []
        if !pending.contains(identifier) {
            pending.append(identifier)
            sharedDefaults?.set(pending, forKey: "pendingBackgroundDownloads")
        }
        pendingDownloads = pending
        
        logger.info("📥 [BackgroundDownload] Scheduled: \(identifier, privacy: .public) — essential: \(essential)")
    }
    
    /// Cancels a previously scheduled download.
    func cancelDownload(identifier: String) async throws {
        let currentDownloads = try await BADownloadManager.shared.currentDownloads
        if let download = currentDownloads.first(where: { $0.identifier == identifier }) {
            try BADownloadManager.shared.cancel(download)
            logger.info("🚫 [BackgroundDownload] Cancelled: \(identifier, privacy: .public)")
        }
        
        // Remove from pending list
        var pending = sharedDefaults?.stringArray(forKey: "pendingBackgroundDownloads") ?? []
        pending.removeAll { $0 == identifier }
        sharedDefaults?.set(pending, forKey: "pendingBackgroundDownloads")
        pendingDownloads = pending
    }
    
    // MARK: - Status
    
    /// Reads the latest status from the shared app group UserDefaults.
    func refresh() {
        guard let defaults = sharedDefaults else {
            logger.warning("⚠️ [BackgroundDownload] Could not open shared UserDefaults for group: \(self.appGroupIdentifier)")
            return
        }
        
        let timestamp = defaults.double(forKey: "lastBackgroundDownloadTimestamp")
        if timestamp > 0 {
            lastDownloadDate = Date(timeIntervalSince1970: timestamp)
        }
        
        downloadedAssetCount = defaults.integer(forKey: "backgroundDownloadedAssetCount")
        lastError = defaults.string(forKey: "lastBackgroundDownloadError")
        pendingDownloads = defaults.stringArray(forKey: "pendingBackgroundDownloads") ?? []
        
        logger.info("📊 [BackgroundDownload] Status — assets: \(self.downloadedAssetCount), pending: \(self.pendingDownloads.count), lastError: \(self.lastError ?? "none", privacy: .public)")
    }
    
    /// URL of the shared container directory where the extension stores downloaded assets.
    var sharedAssetsDirectoryURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )?.appendingPathComponent("BackgroundAssets", isDirectory: true)
    }
    
    /// Lists all files in the shared assets directory.
    func downloadedAssetFiles() -> [URL] {
        guard let dir = sharedAssetsDirectoryURL,
              FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }
        
        do {
            return try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: .skipsHiddenFiles
            )
        } catch {
            logger.error("❌ [BackgroundDownload] Could not list assets: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Clears the error state in shared storage.
    func clearError() {
        sharedDefaults?.removeObject(forKey: "lastBackgroundDownloadError")
        lastError = nil
    }
    
    // MARK: - Private
    
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
