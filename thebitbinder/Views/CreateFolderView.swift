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
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Name") {
                    TextField("Enter folder name", text: $folderName)
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createFolder()
                    }
                    .disabled(folderName.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(.blue)
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func createFolder() {
        let folder = JokeFolder(name: folderName)
        modelContext.insert(folder)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(" [CreateFolderView] Failed to save folder: \(error)")
            saveErrorMessage = "Could not create folder: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
