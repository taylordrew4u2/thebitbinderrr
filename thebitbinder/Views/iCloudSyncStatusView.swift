//
//  iCloudSyncStatusView.swift
//  thebitbinder
//
//  Comprehensive iCloud sync status and troubleshooting view
//

import SwiftUI
import CloudKit

struct iCloudSyncStatusView: View {
    @StateObject private var syncService = iCloudSyncService.shared
    @StateObject private var diagnostics = iCloudSyncDiagnostics.shared
    private let kvStore = iCloudKeyValueStore.shared
    
    @State private var showingDiagnostics = false
    @State private var isRefreshing = false
    
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
                    forceKVSyncRow
                    diagnosticsRow
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
    
    private var forceKVSyncRow: some View {
        Button {
            diagnostics.forceKeyValueSync()
        } label: {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(.blue)
                Text("Force Settings Sync")
                    .foregroundColor(.primary)
            }
        }
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
                Text("Checking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .task {
            _ = await syncService.checkiCloudAvailability()
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
            return .blue
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
        await diagnostics.runComprehensiveDiagnostics()
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
            return .blue
        case .info:
            return .blue
        }
    }
}

struct DiagnosticsDetailView: View {
    @StateObject private var diagnostics = iCloudSyncDiagnostics.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Diagnostic Results") {
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
                }
            }
        }
    }
}

#Preview {
    iCloudSyncStatusView()
}