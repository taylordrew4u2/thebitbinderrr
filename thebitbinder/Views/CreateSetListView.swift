//
//  CreateSetListView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct CreateSetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var name = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Set List Name") {
                    TextField("Enter set list name", text: $name)
                }
            }
            .navigationTitle("New Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSetList()
                    }
                    .disabled(name.isEmpty)
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
    
    private func createSetList() {
        let setList = SetList(name: name)
        modelContext.insert(setList)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(" [CreateSetListView] Failed to save set list: \(error)")
            saveErrorMessage = "Could not create set list: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
