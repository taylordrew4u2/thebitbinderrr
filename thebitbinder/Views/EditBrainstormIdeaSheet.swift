//
//  EditBrainstormIdeaSheet.swift
//  thebitbinder
//
//  Sheet for editing brainstorm ideas
//

import SwiftUI
import SwiftData

struct EditBrainstormIdeaSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false

    @Bindable var idea: BrainstormIdea
    @State private var content: String = ""

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

                    // Metadata
                    HStack {
                        Text("Created \(idea.dateCreated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 12, design: .serif))
                            .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Delete button
                    Button(role: .destructive) {
                        idea.moveToTrash()
                        do {
                            try modelContext.save()
                        } catch {
                            print("❌ [EditBrainstormIdeaSheet] Failed to save after soft-delete: \(error)")
                        }
                        dismiss()
                    } label: {
                        Label("Delete Thought", systemImage: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.Colors.error)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.medium).fill(AppTheme.Colors.error.opacity(0.1)))
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(roastMode ? "🔥 Edit Thought" : "Edit Thought")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .fontWeight(.semibold)
                        .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { content = idea.content }
    }

    private func saveChanges() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        idea.content = trimmed
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BrainstormIdea.self, configurations: config)
    let idea = BrainstormIdea(content: "What if airlines charged by weight?", colorHex: "FFF9C4")
    return EditBrainstormIdeaSheet(idea: idea)
        .modelContainer(container)
}
