//
//  CreateFolderView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct CreateFolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var folderName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Folder Name")) {
                    TextField("Enter folder name", text: $folderName)
                }
            }
            .scrollContentBackground(roastMode ? .hidden : .visible)
            .background(roastMode ? AppTheme.Colors.roastBackground : Color.clear)
            .navigationTitle(roastMode ? "🔥 New Folder" : "New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createFolder()
                    }
                    .disabled(folderName.isEmpty)
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
            }
        }
        .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
    }
    
    private func createFolder() {
        let folder = JokeFolder(name: folderName)
        modelContext.insert(folder)
        do {
            try modelContext.save()
        } catch {
            print("❌ [CreateFolderView] Failed to save new folder: \(error)")
        }
        dismiss()
    }
}
