//
//  JokeDetailView.swift
//  thebitbinder
//
//  Refactored for cleaner, writer-focused experience
//  Progressive disclosure, distraction-free editing, clear hierarchy
//

import SwiftUI
import SwiftData

struct JokeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var folders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @Bindable var joke: Joke
    @State private var isEditing = false
    @State private var showingFolderPicker = false
    @State private var showingDeleteAlert = false
    @State private var showingMetadata = false
    
    // Accent color based on mode
    private var accentColor: Color {
        roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Title Section
                titleSection
                
                // MARK: - Content Section
                contentSection
                
                // MARK: - Tags Section
                if !joke.tags.isEmpty || isEditing {
                    tagsSection
                }
                
                // MARK: - Actions Bar
                actionsBar
                
                // MARK: - Metadata (collapsible)
                if showingMetadata {
                    metadataSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
        .navigationBarTitleDisplayMode(.inline)
        .bitBinderToolbar(roastMode: roastMode)
        .toolbar { toolbarContent }
        .tint(accentColor)
        .alert(joke.isDeleted ? "Restore Joke" : "Move to Trash", isPresented: $showingDeleteAlert) {
            deleteAlertButtons
        } message: {
            Text(joke.isDeleted
                ? "Restore this joke from Trash?"
                : "Are you sure? You can restore it from Trash later.")
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView(selectedFolder: $joke.folder, folders: folders)
        }
        .onDisappear {
            // Auto-save edits — always update word count on exit
            joke.dateModified = Date()
            joke.updateWordCount()
        }
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if isEditing {
                    TextField("Title", text: $joke.title, axis: .vertical)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                        .lineLimit(3)
                } else {
                    Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                }
                
                Spacer()
                
                // Hit badge
                if joke.isHit {
                    HitStarBadge(size: 24, showBackground: true, roastMode: roastMode)
                }
            }
            
            // Word count + folder inline
            HStack(spacing: 12) {
                if joke.wordCount > 0 {
                    Text("\(joke.wordCount) words")
                        .font(.system(size: 12))
                        .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                }
                
                if let folder = joke.folder {
                    Button {
                        showingFolderPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                            Text(folder.name)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(accentColor.opacity(0.8))
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                TextEditor(text: $joke.content)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17))
                    .foregroundColor(roastMode ? .white.opacity(0.92) : AppTheme.Colors.inkBlack)
                    .lineSpacing(6)
                    .frame(minHeight: 250)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                    )
            } else {
                Text(joke.content)
                    .font(.system(size: 17))
                    .foregroundColor(roastMode ? .white.opacity(0.9) : AppTheme.Colors.textPrimary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(roastMode ? AppTheme.Colors.roastCard.opacity(0.5) : AppTheme.Colors.surfaceElevated.opacity(0.5))
                    )
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(joke.tags, id: \.self) { tag in
                        BitBinderChip(
                            text: tag,
                            icon: "tag.fill",
                            style: .tag,
                            roastMode: roastMode
                        )
                    }
                    
                    if joke.tags.isEmpty {
                        Text("No tags")
                            .font(.system(size: 13))
                            .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                            .italic()
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Actions Bar
    
    private var actionsBar: some View {
        HStack(spacing: 12) {
            // Hit Toggle
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    joke.isHit.toggle()
                    joke.dateModified = Date()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: roastMode ? (joke.isHit ? "flame.fill" : "flame") : (joke.isHit ? "star.fill" : "star"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(joke.isHit ? "In Hits" : "Add to Hits")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(
                    joke.isHit
                        ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold)
                        : (roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .fill(
                            joke.isHit
                                ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold).opacity(0.15)
                                : (roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.paperDeep)
                        )
                )
            }
            .buttonStyle(ChipStyle())
            
            // Folder picker
            Button {
                showingFolderPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                    Text(joke.folder?.name ?? "Add Folder")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.paperDeep)
                )
            }
            .buttonStyle(ChipStyle())
            
            Spacer()
            
            // Show/hide metadata
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingMetadata.toggle()
                }
            } label: {
                Image(systemName: showingMetadata ? "chevron.up.circle.fill" : "info.circle")
                    .font(.system(size: 20))
                    .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Metadata Section (progressive disclosure)
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.bottom, 8)
            
            Text("Details")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            VStack(spacing: 12) {
                metadataRow(icon: "calendar", label: "Created", value: joke.dateCreated.formatted(date: .abbreviated, time: .shortened))
                metadataRow(icon: "pencil", label: "Modified", value: joke.dateModified.formatted(date: .abbreviated, time: .shortened))
                
                if let source = joke.importSource, !source.isEmpty {
                    metadataRow(icon: "doc.text", label: "Imported from", value: source)
                }
                
                if let confidence = joke.importConfidence, !confidence.isEmpty {
                    HStack {
                        Label("Confidence", systemImage: "checkmark.seal")
                            .font(.system(size: 13))
                            .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                        Spacer()
                        ConfidenceBadge(
                            level: confidence == "high" ? .high : (confidence == "medium" ? .medium : .low),
                            roastMode: roastMode
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: 13))
                .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(roastMode ? .white : AppTheme.Colors.textPrimary)
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        joke.dateModified = Date()
                        joke.updateWordCount()
                    }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isEditing.toggle()
                    }
                }
                .fontWeight(isEditing ? .semibold : .regular)
                .foregroundColor(accentColor)
                
                if joke.isDeleted {
                    Button {
                        joke.restoreFromTrash()
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(AppTheme.Colors.success)
                    }
                } else {
                    Button {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(AppTheme.Colors.error)
                    }
                }
            }
        }
    }
    
    // MARK: - Delete Alert Buttons
    
    @ViewBuilder
    private var deleteAlertButtons: some View {
        if joke.isDeleted {
            Button("Restore") {
                joke.restoreFromTrash()
                dismiss()
            }
        } else {
            Button("Move to Trash", role: .destructive) {
                joke.moveToTrash()
                dismiss()
            }
        }
        Button("Cancel", role: .cancel) { }
    }
}

// MARK: - Folder Picker

struct FolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedFolder: JokeFolder?
    let folders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    var body: some View {
        NavigationView {
            List {
                Button {
                    selectedFolder = nil
                    dismiss()
                } label: {
                    HStack {
                        Label("No Folder", systemImage: "tray")
                            .foregroundColor(roastMode ? .white : .primary)
                        Spacer()
                        if selectedFolder == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                        }
                    }
                }
                
                ForEach(folders) { folder in
                    Button {
                        selectedFolder = folder
                        dismiss()
                    } label: {
                        HStack {
                            Label(folder.name, systemImage: "folder.fill")
                                .foregroundColor(roastMode ? .white : .primary)
                            Spacer()
                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
