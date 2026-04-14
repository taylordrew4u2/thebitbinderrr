//
//  AddBrainstormIdeaSheet.swift
//  thebitbinder
//
//  Sheet for adding new brainstorm ideas
//

import SwiftUI
import SwiftData

struct AddBrainstormIdeaSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var content = ""
    @State private var isVoiceNote: Bool
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    let initialText: String

    init(isVoiceNote: Bool = false, initialText: String = "") {
        _isVoiceNote = State(initialValue: isVoiceNote)
        self.initialText = initialText
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text(roastMode ? "What's the burn?" : "What's on your mind?")
                                .font(.body)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        
                        TextEditor(text: $content)
                            .scrollContentBackground(.hidden)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(minHeight: 160)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
             .toolbar {
                 ToolbarItem(placement: .cancellationAction) {
                     Button("Cancel") { dismiss() }
                         .foregroundColor(.blue)
                 }
                 ToolbarItem(placement: .confirmationAction) {
                     Button("Save") { saveIdea() }
                         .fontWeight(.semibold)
                         .foregroundColor(.blue)
                         .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                 }
             }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            if !initialText.isEmpty { content = initialText }
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func saveIdea() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let idea = BrainstormIdea(content: trimmed, colorHex: BrainstormIdea.randomColor(), isVoiceNote: isVoiceNote)
        modelContext.insert(idea)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(" [AddBrainstormIdeaSheet] Failed to save idea: \(error)")
            saveErrorMessage = "Could not save thought: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}

#Preview {
    AddBrainstormIdeaSheet()
        .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
