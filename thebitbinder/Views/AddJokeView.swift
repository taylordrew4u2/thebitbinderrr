//
//  AddJokeView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//  ✨ Enhanced for effortless joke capture
//

import SwiftUI
import SwiftData

struct AddJokeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var folders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var title = ""
    @State private var content = ""
    @State private var autoAssign = UserDefaults.standard.bool(forKey: "autoOrganizeEnabled")
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false
    @FocusState private var contentFocused: Bool
    var selectedFolder: JokeFolder?
    
    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Title field - optional, clean
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TITLE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                                .tracking(0.5)
                            
                            TextField("Optional title...", text: $title)
                                .font(.system(size: 18, weight: .medium, design: .serif))
                                .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                        .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                                )
                        }
                        
                        // Content field - primary focus
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("JOKE")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                                    .tracking(0.5)
                                
                                Spacer()
                                
                                if !content.isEmpty {
                                    Text("\(content.split(separator: " ").count) words")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(roastMode ? .white.opacity(0.3) : AppTheme.Colors.textTertiary)
                                }
                            }
                            
                            TextEditor(text: $content)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 17))
                                .foregroundColor(roastMode ? .white.opacity(0.92) : AppTheme.Colors.inkBlack)
                                .lineSpacing(6)
                                .frame(minHeight: 200)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                        .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                                )
                                .focused($contentFocused)
                        }
                        
                        // Folder indicator
                        if let folder = selectedFolder {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                                Text("Will be added to \"\(folder.name)\"")
                                    .font(.system(size: 13))
                                    .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                    .fill((roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction).opacity(0.1))
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Joke")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticEngine.shared.tap()
                        dismiss()
                    }
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveJoke()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave || isSaving)
                    .foregroundColor(canSave ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction) : .gray)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            contentFocused = false
                            HapticEngine.shared.tap()
                        }
                        .fontWeight(.medium)
                    }
                }
            }
            .onAppear {
                // Auto-focus content field after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    contentFocused = true
                }
            }
        }
        .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func saveJoke() {
        isSaving = true
        HapticEngine.shared.tap()
        
        // Small delay to show saving state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let joke = Joke(content: content, title: title, folder: selectedFolder)
            modelContext.insert(joke)
            
            do {
                try modelContext.save()
                HapticEngine.shared.success()
                NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
                dismiss()
            } catch {
                isSaving = false
                HapticEngine.shared.error()
                print("❌ [AddJokeView] Failed to save joke: \(error)")
                saveErrorMessage = "Could not save joke: \(error.localizedDescription)"
                showSaveError = true
            }
        }
    }
}
