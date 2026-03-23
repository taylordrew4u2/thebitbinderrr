//
//  DataSafetyView.swift
//  thebitbinder
//
//  Created for user-facing data protection controls
//

import SwiftUI
import SwiftData
import MessageUI

struct DataSafetyView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var dataProtection = DataProtectionService.shared
    @StateObject private var dataValidation = DataValidationService.shared
    @StateObject private var dataMigration = DataMigrationService.shared
    
    @Query private var jokes: [Joke]
    @Query private var recordings: [Recording]
    @Query private var roastTargets: [RoastTarget]
    
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var isValidating = false
    @State private var isCreatingBackup = false
    @State private var validationResult: DataValidationResult?
    @State private var showingBackups = false
    @State private var availableBackups: [BackupInfo] = []
    
    // Export state
    @State private var showExportOptions = false
    @State private var showAudioExportOptions = false
    @State private var showRoastExportOptions = false
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var showSavedAlert = false
    @State private var savedAlertMessage = ""
    @State private var showMailComposer = false
    @State private var mailAttachmentURL: URL?
    @State private var mailSubject = ""
    @State private var showMailUnavailableAlert = false
    
    var body: some View {
        NavigationView {
            List {
                #if DEBUG
                // Status Section (debug only)
                Section("Data Protection Status") {
                    StatusRow(
                        title: "Data Validation",
                        status: validationResult?.isHealthy == true ? "Healthy" : "Needs Check",
                        isHealthy: validationResult?.isHealthy == true
                    )
                    
                    StatusRow(
                        title: "Available Backups",
                        status: "\(availableBackups.count) backups",
                        isHealthy: availableBackups.count > 0
                    )
                    
                    if let lastBackup = availableBackups.first {
                        StatusRow(
                            title: "Last Backup",
                            status: RelativeDateTimeFormatter().localizedString(for: lastBackup.createdAt, relativeTo: Date()),
                            isHealthy: true
                        )
                    }
                    
                    // Disk space warning
                    let freeSpace = Self.freeDiskSpaceBytes()
                    let freeSpaceFormatted = ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)
                    let isLowSpace = freeSpace < 200 * 1024 * 1024 // 200 MB
                    StatusRow(
                        title: "Free Disk Space",
                        status: isLowSpace ? "⚠️ Low: \(freeSpaceFormatted)" : freeSpaceFormatted,
                        isHealthy: !isLowSpace
                    )
                }
                #endif
                
                // Actions Section
                Section("Backups") {
                    #if DEBUG
                    Button {
                        Task {
                            await validateData()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Validate Data Integrity")
                                    .foregroundColor(.primary)
                                Text("Check for data corruption or loss")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isValidating)
                    #endif
                    
                    Button {
                        Task {
                            await createBackup()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive.badge.plus")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Create Backup")
                                    .foregroundColor(.primary)
                                Text("Manually create a data backup")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isCreatingBackup {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isCreatingBackup)
                    
                    Button {
                        showingBackups = true
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive")
                                .foregroundColor(.orange)
                            Text("View Backups")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                
                
                // MARK: - Export
                Section {
                    Button {
                        showExportOptions = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Export All Jokes")
                                    .foregroundColor(.primary)
                                Text("\(jokes.count) jokes available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .disabled(jokes.isEmpty)
                    
                    Button {
                        showAudioExportOptions = true
                    } label: {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text("Export All Audio Files")
                                    .foregroundColor(.primary)
                                Text("\(recordings.count) recordings available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .disabled(recordings.isEmpty)
                    
                    if roastMode {
                        Button {
                            showRoastExportOptions = true
                        } label: {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(AppTheme.Colors.roastAccent)
                                VStack(alignment: .leading) {
                                    Text("Export Roasts")
                                        .foregroundColor(.primary)
                                    let roastCount = roastTargets.reduce(0) { $0 + $1.jokeCount }
                                    Text("\(roastTargets.count) targets · \(roastCount) roasts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .disabled(roastTargets.isEmpty)
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Export your jokes as a PDF or your audio recordings as a zip archive.")
                }
                
                
                #if DEBUG
                // Information Section (debug only)
                if let result = validationResult {
                    Section("Last Validation Results") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Total Entities:")
                                Spacer()
                                Text("\(result.totalEntities)")
                                    .fontWeight(.semibold)
                            }
                            
                            HStack {
                                Text("Validation Date:")
                                Spacer()
                                Text(result.validationDate, style: .relative)
                                    .fontWeight(.semibold)
                            }
                            
                            if !result.issues.isEmpty {
                                Text("Issues Found:")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                                
                                ForEach(result.issues.indices, id: \.self) { index in
                                    Text("• \(result.issues[index])")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            if result.significantDataLoss {
                                Text("⚠️ SIGNIFICANT DATA LOSS DETECTED")
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                #endif
            }
            .navigationTitle("Data Safety")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await loadBackupInfo()
                if validationResult != nil {
                    await validateData()
                }
            }
        }
        .sheet(isPresented: $showingBackups) {
            BackupsView(backups: availableBackups)
        }
        .confirmationDialog("Export Jokes", isPresented: $showExportOptions) {
            Button("Save PDF to Device") {
                exportJokesAndSave()
            }
            Button("Send via Email") {
                exportJokesAndEmail()
            }
            Button("Share...") {
                exportJokesAndShare()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("How would you like to export your \(jokes.count) jokes?")
        }
        .confirmationDialog("Export Audio", isPresented: $showAudioExportOptions) {
            Button("Save to Device") {
                exportAudioAndSave()
            }
            Button("Send via Email") {
                exportAudioAndEmail()
            }
            Button("Share...") {
                exportAudioAndShare()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("How would you like to export your \(recordings.count) audio files?")
        }
        .confirmationDialog("Export Roasts", isPresented: $showRoastExportOptions) {
            Button("Save PDF to Device") {
                exportRoastsAndSave()
            }
            Button("Send via Email") {
                exportRoastsAndEmail()
            }
            Button("Share...") {
                exportRoastsAndShare()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let roastCount = roastTargets.reduce(0) { $0 + $1.jokeCount }
            Text("Export \(roastCount) roasts across \(roastTargets.count) targets as a PDF?")
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") { }
        } message: {
            Text(savedAlertMessage)
        }
        .alert("Email Unavailable", isPresented: $showMailUnavailableAlert) {
            Button("OK") { }
        } message: {
            Text("Mail is not configured on this device. Please set up a mail account in Settings, or use the Share option instead.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showMailComposer) {
            if let url = mailAttachmentURL {
                MailComposerView(
                    subject: mailSubject,
                    attachmentURL: url,
                    isPresented: $showMailComposer
                )
            }
        }
        .task {
            await loadBackupInfo()
        }
    }
    
    // MARK: - Disk Space
    
    /// Returns the available free disk space in bytes.
    static func freeDiskSpaceBytes() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSpace = attributes[.systemFreeSize] as? Int64 {
                return freeSpace
            }
        } catch {
            print("⚠️ [DataSafety] Could not determine free disk space: \(error)")
        }
        return Int64.max // Assume plenty of space if we can't check
    }
    
    // MARK: - Actions
    
    private func validateData() async {
        isValidating = true
        validationResult = await dataValidation.validateDataIntegrity(context: modelContext)
        isValidating = false
    }
    
    private func createBackup() async {
        isCreatingBackup = true
        await dataProtection.createBackup(reason: .manual)
        await loadBackupInfo()
        isCreatingBackup = false
    }
    
    private func loadBackupInfo() async {
        availableBackups = dataProtection.getAvailableBackups()
    }
    
    // MARK: - Joke Export
    
    private func exportJokesAndSave() {
        guard let url = PDFExportService.exportJokesToPDF(jokes: Array(jokes), fileName: "BitBinder_AllJokes") else { return }
        savedAlertMessage = "PDF saved to your device's Documents folder."
        showSavedAlert = true
        exportedFileURL = url
    }
    
    private func exportJokesAndEmail() {
        guard let url = PDFExportService.exportJokesToPDF(jokes: Array(jokes), fileName: "BitBinder_AllJokes") else { return }
#if !targetEnvironment(macCatalyst)
        if MFMailComposeViewController.canSendMail() {
            mailAttachmentURL = url
            mailSubject = "My BitBinder Jokes"
            showMailComposer = true
        } else {
            showMailUnavailableAlert = true
        }
#else
        exportedFileURL = url
        showShareSheet = true
#endif
    }
    
    private func exportJokesAndShare() {
        guard let url = PDFExportService.exportJokesToPDF(jokes: Array(jokes), fileName: "BitBinder_AllJokes") else { return }
        exportedFileURL = url
        showShareSheet = true
    }
    
    // MARK: - Roast Export
    
    private func exportRoastsAndSave() {
        guard let url = PDFExportService.exportRoastsToPDF(targets: Array(roastTargets), fileName: "BitBinder_Roasts") else { return }
        savedAlertMessage = "Roast PDF saved to your device's Documents folder."
        showSavedAlert = true
        exportedFileURL = url
    }
    
    private func exportRoastsAndEmail() {
        guard let url = PDFExportService.exportRoastsToPDF(targets: Array(roastTargets), fileName: "BitBinder_Roasts") else { return }
#if !targetEnvironment(macCatalyst)
        if MFMailComposeViewController.canSendMail() {
            mailAttachmentURL = url
            mailSubject = "My BitBinder Roasts 🔥"
            showMailComposer = true
        } else {
            showMailUnavailableAlert = true
        }
#else
        exportedFileURL = url
        showShareSheet = true
#endif
    }
    
    private func exportRoastsAndShare() {
        guard let url = PDFExportService.exportRoastsToPDF(targets: Array(roastTargets), fileName: "BitBinder_Roasts") else { return }
        exportedFileURL = url
        showShareSheet = true
    }
    
    // MARK: - Audio Export
    
    private func exportAudioAndSave() {
        Task {
            let url = await createAudioArchive()
            guard let url else { return }
            await MainActor.run {
                savedAlertMessage = "Audio archive saved to your device's Documents folder."
                showSavedAlert = true
                exportedFileURL = url
            }
        }
    }
    
    private func exportAudioAndEmail() {
        Task {
            let url = await createAudioArchive()
            guard let url else { return }
            await MainActor.run {
#if !targetEnvironment(macCatalyst)
                if MFMailComposeViewController.canSendMail() {
                    mailAttachmentURL = url
                    mailSubject = "My BitBinder Audio Recordings"
                    showMailComposer = true
                } else {
                    showMailUnavailableAlert = true
                }
#else
                exportedFileURL = url
                showShareSheet = true
#endif
            }
        }
    }
    
    private func exportAudioAndShare() {
        Task {
            let url = await createAudioArchive()
            guard let url else { return }
            await MainActor.run {
                exportedFileURL = url
                showShareSheet = true
            }
        }
    }
    
    /// Copies all audio recordings into a folder and creates a zip archive
    private func createAudioArchive() async -> URL? {
        let fm = FileManager.default
        let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportFolder = documentsURL.appendingPathComponent("BitBinder_Audio_Export", isDirectory: true)
        let zipURL = documentsURL.appendingPathComponent("BitBinder_Audio.zip")
        
        // Clean up previous exports
        try? fm.removeItem(at: exportFolder)
        try? fm.removeItem(at: zipURL)
        
        do {
            try fm.createDirectory(at: exportFolder, withIntermediateDirectories: true)
            
            var copiedCount = 0
            for recording in recordings {
                let sourceURL = URL(fileURLWithPath: recording.fileURL)
                guard fm.fileExists(atPath: sourceURL.path) else { continue }
                
                let safeName = recording.title
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
                let destURL = exportFolder.appendingPathComponent("\(safeName).\(ext)")
                
                try fm.copyItem(at: sourceURL, to: destURL)
                copiedCount += 1
            }
            
            guard copiedCount > 0 else {
                await MainActor.run {
                    savedAlertMessage = "No audio files found on device."
                    showSavedAlert = true
                }
                return nil
            }
            
            // Create zip archive
            let coordinator = NSFileCoordinator()
            var archiveError: NSError?
            var resultURL: URL?
            
            coordinator.coordinate(readingItemAt: exportFolder, options: .forUploading, error: &archiveError) { tempZipURL in
                try? fm.copyItem(at: tempZipURL, to: zipURL)
                resultURL = zipURL
            }
            
            // Clean up export folder
            try? fm.removeItem(at: exportFolder)
            
            if let error = archiveError {
                #if DEBUG
                print("❌ Audio archive error: \(error)")
                #endif
                return nil
            }
            
            return resultURL
        } catch {
            #if DEBUG
            print("❌ Audio export error: \(error)")
            #endif
            return nil
        }
    }
}

// MARK: - Supporting Views

#if DEBUG
struct StatusRow: View {
    let title: String
    let status: String
    let isHealthy: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isHealthy ? .green : .orange)
            
            VStack(alignment: .leading) {
                Text(title)
                    .fontWeight(.medium)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}
#endif

struct BackupsView: View {
    let backups: [BackupInfo]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataProtection = DataProtectionService.shared
    
    @State private var selectedBackup: BackupInfo?
    @State private var showRestoreConfirmation = false
    @State private var isRestoring = false
    @State private var restoreComplete = false
    @State private var restoreError: String?
    @State private var showRestoreError = false
    @State private var showDeleteConfirmation = false
    @State private var backupToDelete: BackupInfo?
    
    var body: some View {
        NavigationView {
            Group {
                if backups.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "externaldrive.badge.xmark")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No Backups Found")
                            .font(.headline)
                        Text("Create a backup from the Data Safety screen to protect your data.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    List {
                        Section {
                            ForEach(backups) { backup in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(backupDisplayName(backup))
                                                .fontWeight(.semibold)
                                            
                                            Text(backup.createdAt, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            HStack(spacing: 12) {
                                                Text(backup.createdAt, style: .relative)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                
                                                Text(backup.formattedSize)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                
                                                Text("v\(backup.appVersion)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    HStack(spacing: 12) {
                                        // Restore button
                                        Button {
                                            selectedBackup = backup
                                            showRestoreConfirmation = true
                                        } label: {
                                            Label("Restore", systemImage: "arrow.counterclockwise")
                                                .font(.caption.bold())
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(Color.blue)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(isRestoring)
                                        
                                        // Delete button
                                        Button {
                                            backupToDelete = backup
                                            showDeleteConfirmation = true
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundColor(.red.opacity(0.8))
                                                .padding(7)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(Color.red.opacity(0.1))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(isRestoring)
                                        
                                        Spacer()
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text("Tap Restore to recover your data from a backup")
                        } footer: {
                            Text("After restoring, the app will need to restart for changes to take effect. A backup of your current data is created automatically before any restore.")
                        }
                    }
                }
            }
            .navigationTitle("Backups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isRestoring {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.3)
                                .tint(.white)
                            Text("Restoring backup…")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Do not close the app")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    }
                }
            }
            .alert("Restore Backup?", isPresented: $showRestoreConfirmation) {
                Button("Cancel", role: .cancel) {
                    selectedBackup = nil
                }
                Button("Restore", role: .destructive) {
                    if let backup = selectedBackup {
                        performRestore(backup)
                    }
                }
            } message: {
                if let backup = selectedBackup {
                    Text("This will replace ALL current data with the backup from \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)).\n\nYour current data will be backed up first.\n\nThe app will need to restart after restoring.")
                }
            }
            .alert("Restore Complete", isPresented: $restoreComplete) {
                Button("Restart App") {
                    // Force terminate so SwiftData reloads from restored store
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        exit(0)
                    }
                }
            } message: {
                Text("Your data has been restored successfully. The app needs to restart to load the restored data.\n\nTap 'Restart App' and then reopen BitBinder.")
            }
            .alert("Restore Failed", isPresented: $showRestoreError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(restoreError ?? "An unknown error occurred during restore.")
            }
            .alert("Delete Backup?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    backupToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let backup = backupToDelete {
                        deleteBackup(backup)
                    }
                }
            } message: {
                Text("This backup will be permanently deleted. This cannot be undone.")
            }
        }
    }
    
    private func backupDisplayName(_ backup: BackupInfo) -> String {
        if backup.reason == "manual" {
            return "Manual Backup"
        } else if backup.reason == "app_update" {
            return "Auto (App Update)"
        } else if backup.reason == "pre_recovery" {
            return "Pre-Restore Safety"
        } else if backup.reason == "scheduled" {
            return "Scheduled Backup"
        } else {
            return backup.name
        }
    }
    
    private func performRestore(_ backup: BackupInfo) {
        isRestoring = true
        
        Task {
            do {
                try await dataProtection.recoverFromBackup(backup)
                await MainActor.run {
                    isRestoring = false
                    restoreComplete = true
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    restoreError = error.localizedDescription
                    showRestoreError = true
                }
            }
        }
    }
    
    private func deleteBackup(_ backup: BackupInfo) {
        do {
            try FileManager.default.removeItem(at: backup.url)
            backupToDelete = nil
            #if DEBUG
            print("🗑️ [BackupsView] Deleted backup: \(backup.name)")
            #endif
        } catch {
            #if DEBUG
            print("❌ [BackupsView] Failed to delete backup: \(error)")
            #endif
        }
    }
}

#Preview {
    DataSafetyView()
        .modelContainer(for: Joke.self, inMemory: true)
}
