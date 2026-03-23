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
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Set List Name")) {
                    TextField("Enter set list name", text: $name)
                }
            }
            .scrollContentBackground(roastMode ? .hidden : .visible)
            .background(roastMode ? AppTheme.Colors.roastBackground : Color.clear)
            .navigationTitle(roastMode ? "🔥 New Set List" : "New Set List")
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
                        createSetList()
                    }
                    .disabled(name.isEmpty)
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
            }
        }
        .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
    }
    
    private func createSetList() {
        let setList = SetList(name: name)
        modelContext.insert(setList)
        try? modelContext.save()
        dismiss()
    }
}
