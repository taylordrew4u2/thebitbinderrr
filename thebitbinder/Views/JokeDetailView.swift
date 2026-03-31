//
//  JokeDetailView.swift
//  thebitbinder
//
//  Refactored for cleaner, writer-focused experience
//  Progressive disclosure, distraction-free editing, clear hierarchy
//  ✨ Now with auto-save and effortless interactions
//

import SwiftUI
import SwiftData
import Combine

struct JokeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @Bindable var joke: Joke
    @State private var isEditing = false
    @State private var showingFolderPicker = false
    @State private var showingDeleteAlert = false
    @State private var showingMetadata = false
    // Folders loaded lazily — only when the picker sheet opens
    @State private var folders: [JokeFolder] = []
    
    // Auto-save state
    @StateObject private var autoSave = AutoSaveManager.shared
    @State private var showSavedToast = false
    
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
        .successToast(message: "Changes saved", icon: "checkmark.circle.fill", isPresented: $showSavedToast, roastMode: roastMode)
        .alert(joke.isDeleted ? "Restore Joke" : "Move to Trash", isPresented: $showingDeleteAlert) {
            deleteAlertButtons
        } message: {
            Text(joke.isDeleted
                ? "Restore this joke from Trash?"
                : "Are you sure? You can restore it from Trash later.")
        }
        .sheet(isPresented: $showingFolderPicker) {
            MultiFolderPickerView(selectedFolders: $joke.folders, allFolders: folders)
        }
        .onChange(of: showingFolderPicker) { _, isOpen in
            if isOpen {
                folders = (try? modelContext.fetch(FetchDescriptor<JokeFolder>())) ?? []
            }
        }
        // Auto-save on content changes (debounced)
        .onChange(of: joke.content) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: joke.title) { _, _ in
            scheduleAutoSave()
        }
        .onDisappear {
            // Final save on exit
            saveJokeNow()
            folders = []  // free memory
        }
    }
    
    // MARK: - Auto-Save
    
    private func scheduleAutoSave() {
        autoSave.scheduleSave {
            joke.dateModified = Date()
            joke.updateWordCount()
            try? modelContext.save()
        }
    }
    
    private func saveJokeNow() {
        joke.dateModified = Date()
        joke.updateWordCount()
        try? modelContext.save()
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
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Hit badge
                if joke.isHit {
                    HitStarBadge(size: 24, showBackground: true, roastMode: roastMode)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(EffortlessAnimation.snappy, value: isEditing)
            .animation(EffortlessAnimation.bouncy, value: joke.isHit)
            
            // Word count + folders + auto-save status inline
            HStack(spacing: 12) {
                if joke.wordCount > 0 {
                    Text("\(joke.wordCount) words")
                        .font(.system(size: 12))
                        .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                }
                
                if !joke.folders.isEmpty {
                    Button {
                        HapticEngine.shared.tap()
                        showingFolderPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                            if joke.folders.count == 1 {
                                Text(joke.folders[0].name)
                                    .font(.system(size: 12, weight: .medium))
                            } else {
                                Text("\(joke.folders.count) folders")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .foregroundColor(accentColor.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Auto-save status indicator
                if isEditing {
                    SaveStatusIndicator(roastMode: roastMode)
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
                    .transition(.opacity.combined(with: .scale(scale: 0.99, anchor: .top)))
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Tap to edit - feels natural
                        withAnimation(EffortlessAnimation.snappy) {
                            isEditing = true
                        }
                        HapticEngine.shared.tap()
                    }
                    .transition(.opacity)
            }
        }
        .animation(EffortlessAnimation.smooth, value: isEditing)
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
                withAnimation(EffortlessAnimation.bouncy) {
                    joke.isHit.toggle()
                    joke.dateModified = Date()
                }
                HapticEngine.shared.starToggle(joke.isHit)
                
                // Auto-save after toggle
                try? modelContext.save()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: roastMode ? (joke.isHit ? "flame.fill" : "flame") : (joke.isHit ? "star.fill" : "star"))
                        .font(.system(size: 16, weight: .semibold))
                        .symbolEffect(.bounce, value: joke.isHit)
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
            .buttonStyle(SmoothScaleButtonStyle(scale: 0.95, haptic: false))
            
            // Folder picker
            Button {
                HapticEngine.shared.tap()
                showingFolderPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                    if joke.folders.isEmpty {
                        Text("Add Folders")
                            .font(.system(size: 14, weight: .medium))
                    } else if joke.folders.count == 1 {
                        Text(joke.folders[0].name)
                            .font(.system(size: 14, weight: .medium))
                    } else {
                        Text("\(joke.folders.count) folders")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.paperDeep)
                )
            }
            .buttonStyle(SmoothScaleButtonStyle(scale: 0.95))
            
            Spacer()
            
            // Show/hide metadata
            Button {
                withAnimation(EffortlessAnimation.smooth) {
                    showingMetadata.toggle()
                }
                HapticEngine.shared.tap()
            } label: {
                Image(systemName: showingMetadata ? "chevron.up.circle.fill" : "info.circle")
                    .font(.system(size: 20))
                    .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                    .symbolEffect(.bounce, value: showingMetadata)
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
                        // Save on done
                        saveJokeNow()
                        HapticEngine.shared.success()
                        showSavedToast = true
                    } else {
                        HapticEngine.shared.tap()
                    }
                    withAnimation(EffortlessAnimation.snappy) {
                        isEditing.toggle()
                    }
                }
                .fontWeight(isEditing ? .semibold : .regular)
                .foregroundColor(accentColor)
                
                if joke.isDeleted {
                    Button {
                        HapticEngine.shared.success()
                        joke.restoreFromTrash()
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(AppTheme.Colors.success)
                    }
                } else {
                    Button {
                        HapticEngine.shared.warning()
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

// MARK: - Multi-Folder Picker (for many-to-many)

struct MultiFolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedFolders: [JokeFolder]
    let allFolders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    private func isSelected(_ folder: JokeFolder) -> Bool {
        selectedFolders.contains(where: { $0.id == folder.id })
    }
    
    private func toggleFolder(_ folder: JokeFolder) {
        if isSelected(folder) {
            selectedFolders.removeAll(where: { $0.id == folder.id })
        } else {
            selectedFolders.append(folder)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    if selectedFolders.isEmpty {
                        Text("No folders selected")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(selectedFolders) { folder in
                            HStack {
                                Label(folder.name, systemImage: "folder.fill")
                                    .foregroundColor(roastMode ? .white : .primary)
                                Spacer()
                                Button {
                                    toggleFolder(folder)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Selected Folders (\(selectedFolders.count))")
                }
                
                Section {
                    Button {
                        selectedFolders = []
                    } label: {
                        HStack {
                            Label("Clear All Folders", systemImage: "tray")
                                .foregroundColor(roastMode ? .white : .primary)
                            Spacer()
                        }
                    }
                    .disabled(selectedFolders.isEmpty)
                    
                    ForEach(allFolders.filter { !isSelected($0) }) { folder in
                        Button {
                            toggleFolder(folder)
                        } label: {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                    .foregroundColor(roastMode ? .white : .primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                            }
                        }
                    }
                } header: {
                    Text("Available Folders")
                }
            }
            .navigationTitle("Select Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
