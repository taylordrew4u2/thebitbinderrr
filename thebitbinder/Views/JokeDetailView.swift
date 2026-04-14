//
//  JokeDetailView.swift
//  thebitbinder
//
//  Refactored for cleaner, writer-focused experience
//  Progressive disclosure, distraction-free editing, clear hierarchy
//   Now with auto-save and effortless interactions
//

import SwiftUI
import SwiftData

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
    @State private var saveError: String?
    @State private var showingSaveError = false
    
    var body: some View {
        Form {
            // MARK: - Title Section
            Section {
                if isEditing {
                    TextField("Title", text: $joke.title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                } else {
                    HStack {
                        Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                            .font(.title3.weight(.semibold))
                        Spacer()
                        if joke.isOpenMic {
                            Image(systemName: "mic.fill")
                                .foregroundColor(.blue)
                        }
                        if joke.isHit {
                            Image(systemName: roastMode ? "flame.fill" : "star.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            
            // MARK: - Content Section
            Section {
                if isEditing {
                    TextEditor(text: $joke.content)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(minHeight: 200)
                } else {
                    Text(joke.content)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                isEditing = true
                            }
                            HapticEngine.shared.tap()
                        }
                }
            } header: {
                if !joke.content.isEmpty {
                    Text("\(joke.content.split(separator: " ").count) words")
                }
            }
            
            // MARK: - Tags Section
            if !joke.tags.isEmpty {
                Section("Tags") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(joke.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            
            // MARK: - Actions Section
            Section {
                Button {
                    withAnimation {
                        joke.isHit.toggle()
                        joke.dateModified = Date()
                    }
                    HapticEngine.shared.starToggle(joke.isHit)
                    do { try modelContext.save() } catch {
                        saveError = "Couldn't save hit status: \(error.localizedDescription)"
                        showingSaveError = true
                    }
                } label: {
                    Label(
                        joke.isHit ? "Remove from Hits" : "Add to Hits",
                        systemImage: roastMode ? (joke.isHit ? "flame.fill" : "flame") : (joke.isHit ? "star.fill" : "star")
                    )
                    .foregroundColor(joke.isHit ? (.blue) : .accentColor)
                }
                
                Button {
                    withAnimation {
                        joke.isOpenMic.toggle()
                        joke.dateModified = Date()
                    }
                    haptic(.medium)
                    do { try modelContext.save() } catch {
                        saveError = "Couldn't save open mic status: \(error.localizedDescription)"
                        showingSaveError = true
                    }
                } label: {
                    Label(
                        joke.isOpenMic ? "Remove from Open Mic" : "Label for Open Mic",
                        systemImage: joke.isOpenMic ? "mic.slash" : "mic.fill"
                    )
                    .foregroundColor(joke.isOpenMic ? .blue : .blue)
                }
                
                Button {
                    HapticEngine.shared.tap()
                    showingFolderPicker = true
                } label: {
                    HStack {
                        Label("Folders", systemImage: "folder")
                        Spacer()
                        let folderCount = (joke.folders ?? []).count
                        if folderCount == 0 {
                            Text("None")
                                .foregroundColor(.secondary)
                        } else if folderCount == 1 {
                            Text((joke.folders ?? []).first?.name ?? "")
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(folderCount)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // MARK: - Metadata Section (collapsible)
            Section {
                DisclosureGroup("Details", isExpanded: $showingMetadata) {
                    LabeledContent("Created") {
                        Text(joke.dateCreated.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Modified") {
                        Text(joke.dateModified.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let source = joke.importSource, !source.isEmpty {
                        LabeledContent("Imported from") {
                            Text(source)
                        }
                    }
                    if let confidence = joke.importConfidence, !confidence.isEmpty {
                        LabeledContent("Confidence") {
                            Text(confidence.capitalized)
                                .foregroundColor(confidence == "high" ? .blue : (confidence == "medium" ? .blue : .blue))
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .tint(.blue)
        .alert(joke.isDeleted ? "Restore Joke" : "Move to Trash", isPresented: $showingDeleteAlert) {
            deleteAlertButtons
        } message: {
            Text(joke.isDeleted
                ? "Restore this joke from Trash?"
                : "Are you sure? You can restore it from Trash later.")
        }
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your changes might not be saved. Try editing again.")
        }
        .sheet(isPresented: $showingFolderPicker) {
            MultiFolderPickerView(
                selectedFolders: Binding(
                    get: { joke.folders ?? [] },
                    set: { joke.folders = $0 }
                ),
                allFolders: folders
            )
        }
        .onChange(of: showingFolderPicker) { _, isOpen in
            if isOpen {
                var descriptor = FetchDescriptor<JokeFolder>(predicate: #Predicate { !$0.isDeleted })
                descriptor.sortBy = [SortDescriptor(\JokeFolder.name)]
                folders = (try? modelContext.fetch(descriptor)) ?? []
            }
        }
        .onChange(of: joke.content) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: joke.title) { _, _ in
            scheduleAutoSave()
        }
        .onDisappear {
            saveJokeNow()
            folders = []
        }
    }
    
    // MARK: - Auto-Save
    
    private func scheduleAutoSave() {
        autoSave.scheduleSave { [self] in
            joke.dateModified = Date()
            joke.updateWordCount()
            do {
                try modelContext.save()
            } catch {
                print(" [JokeDetailView] Auto-save failed: \(error)")
                saveError = "Your changes couldn't be saved: \(error.localizedDescription)"
                showingSaveError = true
            }
        }
    }
    
    private func saveJokeNow() {
        joke.dateModified = Date()
        joke.updateWordCount()
        do {
            try modelContext.save()
        } catch {
            print(" [JokeDetailView] Save failed: \(error)")
            saveError = "Your changes couldn't be saved: \(error.localizedDescription)"
            showingSaveError = true
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveJokeNow()
                        HapticEngine.shared.success()
                    } else {
                        HapticEngine.shared.tap()
                    }
                    withAnimation {
                        isEditing.toggle()
                    }
                }
                .fontWeight(isEditing ? .semibold : .regular)
                
                if joke.isDeleted {
                    Button {
                        HapticEngine.shared.success()
                        joke.restoreFromTrash()
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(.blue)
                    }
                } else {
                    Button {
                        HapticEngine.shared.warning()
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
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
        NavigationStack {
            List {
                Button {
                    selectedFolder = nil
                    dismiss()
                } label: {
                    HStack {
                        Label("No Folder", systemImage: "tray")
                        Spacer()
                        if selectedFolder == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
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
                            Spacer()
                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
        NavigationStack {
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
                        Label("Clear All Folders", systemImage: "tray")
                    }
                    .disabled(selectedFolders.isEmpty)
                    
                    ForEach(allFolders.filter { !isSelected($0) }) { folder in
                        Button {
                            toggleFolder(folder)
                        } label: {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Available Folders")
                }
            }
            .navigationTitle("Folders")
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
