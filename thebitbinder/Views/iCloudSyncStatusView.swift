//
//  iCloudSyncStatusView.swift
//  thebitbinder
//
//  Comprehensive iCloud sync status and troubleshooting view
//

import SwiftUI
import SwiftData

struct iCloudSyncStatusView: View {
    @StateObject private var syncService = iCloudSyncService.shared
    @StateObject private var diagnostics = iCloudSyncDiagnostics.shared
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingDiagnostics = false
    @State private var isRefreshing = false
    @State private var isForceRefreshing = false
    @State private var isForcingKVSync = false
    @State private var accountStatusText = "Checking..."
    @State private var jokeCount = 0
    @State private var setListCount = 0
    @State private var recordingCount = 0
    @State private var brainstormCount = 0
    
    var body: some View {
        NavigationStack {
            List {
                // Current Sync Status
                Section("Sync Status") {
                    syncStatusRow
                    lastSyncRow
                    syncToggleRow
                }
                
                // Quick Actions
                Section("Quick Actions") {
                    syncNowRow
                    forceRefreshRow
                    forceKVSyncRow
                    diagnosticsRow
                }
                
                // Local Data Counts
                Section("Local Data") {
                    dataCountRow(label: "Jokes", count: jokeCount, icon: "text.quote")
                    dataCountRow(label: "Set Lists", count: setListCount, icon: "list.bullet.rectangle.portrait")
                    dataCountRow(label: "Recordings", count: recordingCount, icon: "waveform")
                    dataCountRow(label: "Brainstorm Ideas", count: brainstormCount, icon: "lightbulb")
                }
                
                // Account Status
                Section("iCloud Account") {
                    accountStatusRow
                }
                
                // Troubleshooting
                if !diagnostics.syncIssuesFound.isEmpty {
                    Section("Issues Found") {
                        ForEach(diagnostics.syncIssuesFound.indices, id: \.self) { index in
                            let issue = diagnostics.syncIssuesFound[index]
                            IssueRowView(issue: issue)
                        }
                    }
                }
            }
            .navigationTitle("iCloud Sync")
            .refreshable {
                await refreshStatus()
            }
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsDetailView()
            }
            .task {
                refreshDataCounts()
                if diagnostics.diagnosticResults.isEmpty {
                    await diagnostics.runComprehensiveDiagnostics()
                }
            }
        }
    }
    
    private var syncStatusRow: some View {
        HStack {
            Image(systemName: syncStatusIcon)
                .foregroundColor(syncStatusColor)
            
            VStack(alignment: .leading) {
                Text("Sync Status")
                    .font(.headline)
                Text(syncStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if case .syncing = syncService.syncStatus {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
    
    private var lastSyncRow: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading) {
                Text("Last Sync")
                    .font(.headline)
                Text(lastSyncText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var syncToggleRow: some View {
        HStack {
            Image(systemName: "icloud")
                .foregroundColor(.blue)
            
            Text("iCloud Sync")
                .font(.headline)
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { syncService.isSyncEnabled },
                set: { enabled in
                    Task {
                        if enabled {
                            await syncService.enableiCloudSync()
                        } else {
                            syncService.disableiCloudSync()
                        }
                    }
                }
            ))
        }
    }
    
    private var syncNowRow: some View {
        Button {
            Task {
                isRefreshing = true
                await syncService.syncNow()
                isRefreshing = false
            }
        } label: {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.blue)
                Text("Sync Now")
                    .foregroundColor(.primary)
                
                if isRefreshing {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .disabled(isRefreshing || !syncService.isSyncEnabled)
    }
    
    private var forceRefreshRow: some View {
        Button {
            Task {
                isForceRefreshing = true
                await syncService.forceRefreshAllData()
                refreshDataCounts()
                isForceRefreshing = false
            }
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                Text("Force Refresh All Data")
                    .foregroundColor(.primary)
                
                if isForceRefreshing {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .disabled(isForceRefreshing || !syncService.isSyncEnabled)
    }
    
    private var forceKVSyncRow: some View {
        Button {
            Task {
                isForcingKVSync = true
                await diagnostics.forceKeyValueSync()
                isForcingKVSync = false
            }
        } label: {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(.blue)
                Text("Force Settings Sync")
                    .foregroundColor(.primary)
                
                if isForcingKVSync {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .disabled(isForcingKVSync)
    }
    
    private var diagnosticsRow: some View {
        Button {
            showingDiagnostics = true
        } label: {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundColor(.blue)
                Text("Run Diagnostics")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var accountStatusRow: some View {
        HStack {
            Image(systemName: "person.icloud")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text("Account Status")
                    .font(.headline)
                Text(accountStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .task {
            let available = await syncService.checkiCloudAvailability()
            accountStatusText = available ? "Signed In" : (syncService.errorMessage ?? "Unavailable")
        }
    }
    
    // MARK: - Helpers
    
    private var syncStatusIcon: String {
        switch syncService.syncStatus {
        case .idle:
            return "pause.circle"
        case .syncing:
            return "arrow.clockwise.circle"
        case .success:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.circle"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncService.syncStatus {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }
    
    private var syncStatusText: String {
        switch syncService.syncStatus {
        case .idle:
            return syncService.isSyncEnabled ? "Ready" : "Disabled"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Up to date"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private var lastSyncText: String {
        if let lastSync = syncService.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: lastSync, relativeTo: Date())
        } else {
            return "Never"
        }
    }
    
    private func refreshStatus() async {
        refreshDataCounts()
        await diagnostics.runComprehensiveDiagnostics()
    }
    
    private func dataCountRow(label: String, count: Int, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            
            Text(label)
                .font(.headline)
            
            Spacer()
            
            Text("\(count)")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    private func refreshDataCounts() {
        do {
            jokeCount = try modelContext.fetchCount(FetchDescriptor<Joke>())
            setListCount = try modelContext.fetchCount(FetchDescriptor<SetList>())
            recordingCount = try modelContext.fetchCount(FetchDescriptor<Recording>())
            brainstormCount = try modelContext.fetchCount(FetchDescriptor<BrainstormIdea>())
        } catch {
            print(" [SyncStatus] Failed to fetch data counts: \(error)")
        }
    }
}

struct IssueRowView: View {
    let issue: iCloudSyncDiagnostics.SyncIssue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: severityIcon)
                    .foregroundColor(severityColor)
                
                Text(issue.description)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text(issue.suggestedFix)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private var severityIcon: String {
        switch issue.severity {
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.triangle"
        case .info:
            return "info.circle"
        }
    }
    
    private var severityColor: Color {
        switch issue.severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }
}

struct DiagnosticsDetailView: View {
    @StateObject private var diagnostics = iCloudSyncDiagnostics.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isManualSyncing = false
    
    var body: some View {
        NavigationStack {
            List {
                if !diagnostics.syncIssuesFound.isEmpty {
                    Section("Issues Found") {
                        ForEach(diagnostics.syncIssuesFound.indices, id: \.self) { index in
                            let issue = diagnostics.syncIssuesFound[index]
                            IssueRowView(issue: issue)
                        }
                    }
                }
                
                Section("Actions") {
                    Button {
                        Task {
                            isManualSyncing = true
                            await diagnostics.triggerManualSync()
                            isManualSyncing = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                            Text("Trigger Manual Sync")
                                .foregroundColor(.primary)
                            
                            if isManualSyncing {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isManualSyncing)
                }
                
                Section("Diagnostic Results") {
                    if diagnostics.isRunningDiagnostics {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Running diagnostics...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ForEach(diagnostics.diagnosticResults, id: \.self) { result in
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Sync Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await diagnostics.runComprehensiveDiagnostics()
                        }
                    }
                    .disabled(diagnostics.isRunningDiagnostics)
                }
            }
        }
    }
}

#Preview {
    iCloudSyncStatusView()
}