//
//  DataSafetyView.swift
//  thebitbinder
//
//  Created for user-facing data protection controls
//

import SwiftUI
import SwiftData

struct DataSafetyView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var dataProtection = DataProtectionService.shared
    @StateObject private var dataValidation = DataValidationService.shared
    @StateObject private var dataMigration = DataMigrationService.shared
    
    @State private var isValidating = false
    @State private var isCreatingBackup = false
    @State private var validationResult: DataValidationResult?
    @State private var showingBackups = false
    @State private var showingLogs = false
    @State private var showingEmergencyRecovery = false
    @State private var availableBackups: [BackupInfo] = []
    
    var body: some View {
        NavigationView {
            List {
                // Status Section
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
                }
                
                // Actions Section
                Section("Data Protection Actions") {
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
                
                // Advanced Section
                Section("Advanced") {
                    Button {
                        showingLogs = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                            Text("View Data Operation Logs")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    Button {
                        showingEmergencyRecovery = true
                    } label: {
                        HStack {
                            Image(systemName: "cross.case")
                                .foregroundColor(.red)
                            Text("Emergency Data Recovery")
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                
                // Information Section
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
        .sheet(isPresented: $showingLogs) {
            DataLogsView()
        }
        .sheet(isPresented: $showingEmergencyRecovery) {
            EmergencyRecoveryView()
        }
        .task {
            await loadBackupInfo()
        }
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
}

// MARK: - Supporting Views

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

struct BackupsView: View {
    let backups: [BackupInfo]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(backups) { backup in
                VStack(alignment: .leading, spacing: 4) {
                    Text(backup.name)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Version \(backup.appVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(backup.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Reason: \(backup.reason)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(backup.formattedSize)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Backups")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

struct DataLogsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(logContent)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Data Operation Logs")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Done") { dismiss() },
                trailing: Button("Share") { shareLog() }
            )
        }
        .task {
            loadLogs()
        }
    }
    
    private func loadLogs() {
        logContent = DataOperationLogger.shared.getCurrentLog() ?? "No logs available"
    }
    
    private func shareLog() {
        if let exportURL = DataOperationLogger.shared.exportLogs() {
            let activityVC = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
    }
}

struct EmergencyRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmation = false
    @State private var isRecovering = false
    @State private var recoveryMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("Emergency Data Recovery")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("This will attempt to recover your data from the most recent backup. This should only be used if you've experienced significant data loss.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ Warning:")
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("• This will overwrite your current data")
                    Text("• A backup will be created before recovery")
                    Text("• This action cannot be undone")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                
                if !recoveryMessage.isEmpty {
                    Text(recoveryMessage)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Spacer()
                
                Button("Begin Emergency Recovery") {
                    showingConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRecovering)
                
                if isRecovering {
                    ProgressView("Recovering data...")
                        .padding()
                }
            }
            .padding()
            .navigationTitle("Emergency Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })
        }
        .alert("Confirm Emergency Recovery", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Recover", role: .destructive) {
                Task {
                    await performEmergencyRecovery()
                }
            }
        } message: {
            Text("Are you absolutely sure you want to perform emergency data recovery? This will overwrite your current data.")
        }
    }
    
    private func performEmergencyRecovery() async {
        isRecovering = true
        
        let result = await DataMigrationService.shared.emergencyDataRecovery()
        
        switch result {
        case .success(let message):
            recoveryMessage = "✅ Recovery successful: \(message)"
        case .warning(let message):
            recoveryMessage = "⚠️ Recovery completed with warnings: \(message)"
        case .failure(let message):
            recoveryMessage = "❌ Recovery failed: \(message)"
        }
        
        isRecovering = false
    }
}

#Preview {
    DataSafetyView()
        .modelContainer(for: Joke.self, inMemory: true)
}