//
//  SettingsView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/22/26.
//

import SwiftUI
import SwiftData
import MessageUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jokes: [Joke]
    @Query private var recordings: [Recording]
    @Query private var roastTargets: [RoastTarget]
    @EnvironmentObject private var userPreferences: UserPreferences
    
    
    @State private var isExportingJokes = false
    @State private var isExportingAudio = false
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
    @State private var showReorderSheet = false
    
    // Layout reorder
    @AppStorage("tabOrder") private var tabOrderData: Data = Data()
    
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Profile
                Section {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Name")
                                    .foregroundColor(.primary)
                                Text("Displayed on launch screen")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        TextField("Your name", text: $userPreferences.userName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                } header: {
                    Text("Profile")
                }
                
                // MARK: - Layout
                Section {
                    Button {
                        showReorderSheet = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reorder Layout")
                                    .foregroundColor(.primary)
                                Text("Drag to rearrange your tabs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "rectangle.3.group")
                                .foregroundColor(.blue)
                        }
                    }
                } header: {
                    Text("Layout")
                }
                
                // MARK: - Roast Mode
                Section {
                    Toggle(isOn: $roastMode) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Roast Mode")
                                    .foregroundColor(.primary)
                                Text(roastMode
                                     ? "Jokes section shows roast targets"
                                     : "Jokes section shows your regular jokes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: roastMode ? "flame.fill" : "flame")
                                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : .gray)
                        }
                    }
                    .tint(AppTheme.Colors.roastAccent)
                } header: {
                    Text("Mode")
                } footer: {
                    Text("When enabled, the Jokes tab becomes a dedicated space for writing roasts about specific people.")
                }
                
                // MARK: - iCloud Sync
                Section {
                    NavigationLink(destination: iCloudSyncSettingsView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iCloud Sync")
                                    .foregroundColor(.primary)
                                Text("Back up and sync your data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "icloud.and.arrow.up.fill")
                                .foregroundColor(AppTheme.Colors.brand)
                        }
                    }
                } header: {
                    Text("Cloud")
                } footer: {
                    Text("Automatically back up all your jokes, roasts, recordings, and photos to iCloud.")
                }
                
                // MARK: - Data Safety
                Section {
                    NavigationLink(destination: DataSafetyView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Data Safety")
                                    .foregroundColor(.primary)
                                Text("Protect against data loss")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(.green)
                        }
                    }
                } header: {
                    Text("Data Protection")
                } footer: {
                    Text("Automatic backups, data validation, and recovery tools to ensure your data is never lost during app updates.")
                }
                
                // MARK: - Daily Notifications
                DailyNotificationSection()
                
                // MARK: - Export Jokes
                Section {
                    Button {
                        showExportOptions = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export All Jokes")
                                    .foregroundColor(.primary)
                                Text("\(jokes.count) jokes available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.text")
                                .foregroundColor(.orange)
                        }
                    }
                    .disabled(jokes.isEmpty)
                    
                    Button {
                        showAudioExportOptions = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export All Audio Files")
                                    .foregroundColor(.primary)
                                Text("\(recordings.count) recordings available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "waveform")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(recordings.isEmpty)
                    
                    if roastMode {
                        Button {
                            showRoastExportOptions = true
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Export Roasts")
                                        .foregroundColor(.primary)
                                    let roastCount = roastTargets.reduce(0) { $0 + $1.jokeCount }
                                    Text("\(roastTargets.count) targets · \(roastCount) roasts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(AppTheme.Colors.roastAccent)
                            }
                        }
                        .disabled(roastTargets.isEmpty)
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Export your jokes as a PDF or your audio recordings as a zip archive.")
                }
                
                // MARK: - Trash
                Section {
                    NavigationLink(destination: TrashView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Trash")
                                    .foregroundColor(.primary)
                                let trashedCount = jokes.filter { $0.isDeleted }.count
                                Text(trashedCount > 0 ? "\(trashedCount) deleted jokes" : "No items in trash")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundColor(.gray)
                        }
                    }
                } header: {
                    Text("Data Management")
                } footer: {
                    Text("View and restore deleted jokes, or permanently empty trash.")
                }
                
                // MARK: - Help
                Section {
                    NavigationLink(destination: HelpFAQView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Help & FAQ")
                                    .foregroundColor(.primary)
                                Text("Guides, tips, and answers")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundColor(.purple)
                        }
                    }
                } header: {
                    Text("Support")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("9.4")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Chat Assistant")
                        Spacer()
                        Text("BitBuddy")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $showReorderSheet) {
                ReorderLayoutView()
            }
        }
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
                
                let safeName = recording.name
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
                print("❌ Audio archive error: \(error)")
                return nil
            }
            
            return resultURL
        } catch {
            print("❌ Audio export error: \(error)")
            return nil
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mail Composer

#if !targetEnvironment(macCatalyst)
struct MailComposerView: UIViewControllerRepresentable {
    let subject: String
    let attachmentURL: URL
    @Binding var isPresented: Bool
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody("Exported from The BitBinder app.", isHTML: false)
        if let data = try? Data(contentsOf: attachmentURL) {
            let ext = attachmentURL.pathExtension.lowercased()
            let mimeType = ext == "pdf" ? "application/pdf" : ext == "zip" ? "application/zip" : "application/octet-stream"
            vc.addAttachmentData(data, mimeType: mimeType, fileName: attachmentURL.lastPathComponent)
        }
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        init(_ parent: MailComposerView) { self.parent = parent }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.isPresented = false
        }
    }
}
#else
struct MailComposerView: View {
    let subject: String
    let attachmentURL: URL
    @Binding var isPresented: Bool
    var body: some View { EmptyView() }
}
#endif

// MARK: - Reorder Layout View

struct ReorderLayoutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tabOrder") private var tabOrderData: Data = Data()
    @State private var screens: [AppScreen] = AppScreen.allCases
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(screens, id: \.self) { screen in
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(screen.color.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: screen.icon)
                                    .foregroundColor(screen.color)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            
                            Text(screen.rawValue)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveScreens)
                } header: {
                    Text("Drag to reorder your tabs")
                } footer: {
                    Text("This controls the order screens appear in your navigation menu.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveOrder()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadOrder()
            }
        }
    }
    
    private func moveScreens(from source: IndexSet, to destination: Int) {
        screens.move(fromOffsets: source, toOffset: destination)
    }
    
    private func saveOrder() {
        let rawValues = screens.map { $0.rawValue }
        if let data = try? JSONEncoder().encode(rawValues) {
            tabOrderData = data
        }
    }
    
    private func loadOrder() {
        guard !tabOrderData.isEmpty,
              let rawValues = try? JSONDecoder().decode([String].self, from: tabOrderData) else { return }
        let ordered = rawValues.compactMap { raw in AppScreen(rawValue: raw) }
        if ordered.count == AppScreen.allCases.count {
            screens = ordered
        }
    }
}

// MARK: - Daily Notification Settings

struct DailyNotificationSection: View {
    @ObservedObject private var manager = NotificationManager.shared

    // Convert minutes-from-midnight ↔ Date for the DatePicker
    private var startDate: Binding<Date> {
        Binding(
            get: { dateFromMinutes(manager.startMinute) },
            set: { manager.startMinute = minutesFromDate($0) }
        )
    }
    private var endDate: Binding<Date> {
        Binding(
            get: { dateFromMinutes(manager.endMinute) },
            set: { manager.endMinute = minutesFromDate($0) }
        )
    }

    var body: some View {
        Section {
            Toggle(isOn: $manager.isEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Reminder")
                            .foregroundColor(.primary)
                        Text("A random roast to keep you writing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.orange)
                }
            }

            if manager.isEnabled {
                DatePicker("Earliest", selection: startDate, displayedComponents: .hourAndMinute)
                DatePicker("Latest",   selection: endDate,   displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Notifications")
        } footer: {
            if manager.isEnabled {
                Text("You'll get one push notification per day at a random time between these hours.")
            }
        }
    }

    // MARK: - Helpers

    private func dateFromMinutes(_ mins: Int) -> Date {
        Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Joke.self, Recording.self], inMemory: true)
}
