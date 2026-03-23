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
    let initialText: String

    init(isVoiceNote: Bool = false, initialText: String = "") {
        _isVoiceNote = State(initialValue: isVoiceNote)
        self.initialText = initialText
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                            .shadow(color: .black.opacity(0.07), radius: 6, y: 3)

                        if content.isEmpty {
                            Text(roastMode ? "What's the burn?" : "What's on your mind?")
                                .font(.system(size: 17, design: .serif))
                                .foregroundColor(roastMode ? .white.opacity(0.35) : AppTheme.Colors.textTertiary)
                                .padding(16)
                        }

                        TextEditor(text: $content)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .font(.system(size: 17, design: .serif))
                            .foregroundColor(roastMode ? .white.opacity(0.9) : AppTheme.Colors.inkBlack)
                            .padding(12)
                            .frame(minHeight: 160)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()
                }
            }
            .navigationTitle(roastMode ? "🔥 New Fire Thought" : "New Thought")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveIdea() }
                        .fontWeight(.semibold)
                        .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            if !initialText.isEmpty { content = initialText }
        }
    }

    private func saveIdea() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let idea = BrainstormIdea(content: trimmed, colorHex: BrainstormIdea.randomColor(), isVoiceNote: isVoiceNote)
        modelContext.insert(idea)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    AddBrainstormIdeaSheet()
        .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
