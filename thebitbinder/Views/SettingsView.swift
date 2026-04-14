//
//  SettingsView.swift
//  thebitbinder
//
//  Settings screen using standard iOS Settings patterns.
//

import SwiftUI
import SwiftData
import MessageUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jokes: [Joke]
    @EnvironmentObject private var userPreferences: UserPreferences
    
    @AppStorage("roastModeEnabled") private var roastMode = false
    @State private var isEditingName = false
    @State private var editingNameText = ""
    @FocusState private var nameFieldFocused: Bool
    
    var body: some View {
        List {
            // MARK: - Profile Header
            Section {
                HStack(spacing: 14) {
                    // Avatar circle with initial
                    ZStack {
                        Circle()
                            .fill(roastMode ? Color.blue.opacity(0.15) : Color.accentColor.opacity(0.12))
                            .frame(width: 52, height: 52)
                        
                        Text(userPreferences.userName.isEmpty ? "?" : String(userPreferences.userName.prefix(1)).uppercased())
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if isEditingName {
                            TextField("Your name", text: $editingNameText)
                                .font(.body.weight(.semibold))
                                .textFieldStyle(.plain)
                                .focused($nameFieldFocused)
                                .onSubmit { saveName() }
                                .submitLabel(.done)
                        } else {
                            Text(userPreferences.userName.isEmpty ? "Set Your Name" : userPreferences.userName)
                                .font(.body.weight(.semibold))
                                .foregroundColor(userPreferences.userName.isEmpty ? .secondary : .primary)
                        }
                        
                        Text("\(jokes.filter { !$0.isDeleted }.count) jokes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if isEditingName {
                        Button("Done") { saveName() }
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Button {
                            editingNameText = userPreferences.userName
                            isEditingName = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                nameFieldFocused = true
                            }
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Mode Section
            Section {
                Toggle(isOn: $roastMode) {
                    Label("Roast Mode", systemImage: roastMode ? "flame.fill" : "flame")
                }
                .tint(.blue)
            } footer: {
                Text("Organize material by roast target instead of folder.")
            }
            
            // MARK: - Data Section
            Section {
                NavigationLink {
                    iCloudSyncSettingsView()
                } label: {
                    Label("iCloud Sync", systemImage: "icloud")
                }
                
                NavigationLink {
                    DataSafetyView()
                } label: {
                    Label("Data Protection", systemImage: "shield.checkered")
                }
                
                NavigationLink {
                    TrashView()
                } label: {
                    HStack {
                        Label("Trash", systemImage: "trash")
                        Spacer()
                        let trashedCount = jokes.filter { $0.isDeleted }.count
                        if trashedCount > 0 {
                            Text("\(trashedCount)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Data")
            }
            
            
            // MARK: - Notifications Section
            DailyNotificationSection()
            
            // MARK: - Support Section
            Section {
                NavigationLink {
                    HelpFAQView()
                } label: {
                    Label("Help & FAQ", systemImage: "questionmark.circle")
                }
            } header: {
                Text("Support")
            }
            
            // MARK: - About Section
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("10.4")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: nameFieldFocused) { _, focused in
            if !focused && isEditingName {
                saveName()
            }
        }
    }
    
    private func saveName() {
        let trimmed = editingNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            userPreferences.userName = trimmed
        }
        isEditingName = false
        nameFieldFocused = false
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
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
        vc.setMessageBody("Exported from BitBinder.", isHTML: false)
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

// MARK: - Daily Notification Settings

struct DailyNotificationSection: View {
    @ObservedObject private var manager = NotificationManager.shared

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
                Label("Daily Reminder", systemImage: "bell")
            }

            if manager.isEnabled {
                DatePicker("Between", selection: startDate, displayedComponents: .hourAndMinute)
                DatePicker("And", selection: endDate, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Notifications")
        }
    }

    private func dateFromMinutes(_ mins: Int) -> Date {
        Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
    }
    .modelContainer(for: [Joke.self, Recording.self], inMemory: true)
}