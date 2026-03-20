//
//  JokesView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData
import PhotosUI
import PDFKit

struct JokesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jokes: [Joke]
    @Query private var folders: [JokeFolder]
    @Query(sort: \RoastTarget.dateModified, order: .reverse) private var roastTargets: [RoastTarget]
    @Query(sort: \BrainstormIdea.dateCreated, order: .reverse) private var brainstormIdeas: [BrainstormIdea]
    
    // Roast mode — toggled from Settings
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    // Roast sheet state
    @State private var showingAddRoastTarget = false
    @State private var roastTargetToDelete: RoastTarget?
    @State private var showingDeleteRoastAlert = false
    
    @AppStorage("jokesViewMode") private var viewMode: JokesViewMode = .grid
    @AppStorage("roastViewMode") private var roastViewMode: JokesViewMode = .list
    @AppStorage("expandAllJokes") private var expandAllJokes = false
    @AppStorage("jokesGridScale") private var jokesGridScale: Double = 1.0
    @AppStorage("roastGridScale") private var roastGridScale: Double = 1.0

    // Grid columns derived from scale
    private var jokesColumns: [GridItem] {
        let count = max(2, Int(4 / jokesGridScale))
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
    private var roastColumns: [GridItem] {
        let count = max(2, Int(4 / roastGridScale))
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
    
    @State private var showingAddJoke = false
    @State private var showingScanner = false
    @State private var showingImagePicker = false
    @State private var showingFilePicker = false
    @State private var showingCreateFolder = false
    @State private var showingAutoOrganize = false
    @State private var showingImportHistory = false
    @State private var showingExportAlert = false
    @State private var selectedFolder: JokeFolder?
    @State private var showRecentlyAdded = false
    @State private var searchText = ""
    @State private var exportedPDFURL: URL?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isProcessingImages = false
    @State private var processingCurrent: Int = 0
    @State private var processingTotal: Int = 0
    @State private var importSummary: (added: Int, skipped: Int) = (0, 0)
    @State private var showingImportSummary = false
    @State private var folderPendingDeletion: JokeFolder?
    @State private var showingDeleteFolderAlert = false
    @State private var showingMoveJokesSheet = false
    @State private var showingAudioImport = false
    @State private var showingTalkToText = false
    
    @State private var reviewCandidates: [JokeImportCandidate] = []
    @State private var showingReviewSheet = false
    @State private var possibleDuplicates: [String] = []
    @State private var unresolvedImportFragments: [UnresolvedImportFragment] = []
    
    // Live import progress
    @State private var importStatusMessage = ""
    @State private var importedJokeNames: [String] = []
    @State private var importFileCount = 0
    @State private var importFileIndex = 0
    
    // Performance: Debounced search and cached filtered results
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var cachedFilteredJokes: [Joke] = []
    @State private var needsFilterRefresh = true

    // MARK: - The Hits Button
    
    @ViewBuilder
    private var theHitsButton: some View {
        VStack(spacing: 8) {
            NavigationLink(destination: HitsView()) {
                ZStack {
                    // Main circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    // Star icon
                    Image(systemName: "star")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom)
                        )
                }
            }
            .buttonStyle(ChipStyle())
            
            Text("The Hits")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            // Count badge
            let hitsCount = jokes.filter { $0.isHit && !$0.isDeleted }.count
            if hitsCount > 0 {
                Text("\(hitsCount) perfected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }


    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FolderChip(
                    name: "All Jokes",
                    isSelected: selectedFolder == nil && !showRecentlyAdded,
                    action: { selectedFolder = nil; showRecentlyAdded = false }
                )
                FolderChip(
                    name: "Recently Added",
                    icon: "clock.fill",
                    isSelected: showRecentlyAdded,
                    action: { showRecentlyAdded = true; selectedFolder = nil }
                )
                ForEach(folders) { folder in
                    FolderChip(
                        name: folder.name,
                        isSelected: selectedFolder?.id == folder.id && !showRecentlyAdded,
                        action: { selectedFolder = folder; showRecentlyAdded = false }
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            folderPendingDeletion = folder
                            showingDeleteFolderAlert = true
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(AppTheme.Colors.paperAged)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.Colors.jokesAccent.opacity(0.2), AppTheme.Colors.jokesAccent.opacity(0.05)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 110, height: 110)
                
                Image(systemName: "theatermask.and.paintbrush.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.Colors.jokesAccent, AppTheme.Colors.jokesAccent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No jokes yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Add your first joke using the + button")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Roast Section

    @ViewBuilder
    private var roastSection: some View {
        if roastTargets.isEmpty {
            // Empty roast state
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.roastAccent.opacity(0.12))
                        .frame(width: 110, height: 110)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.Colors.roastAccent, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                VStack(spacing: 8) {
                    Text("No roast targets yet")
                        .font(.title3.bold())
                    Text("Add someone you want to roast and start writing jokes just for them")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    showingAddRoastTarget = true
                } label: {
                    Label("Add First Target", systemImage: "person.badge.plus")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Colors.roastAccent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            if roastViewMode == .grid {
                VStack(spacing: 0) {
                    // Zoom slider
                    HStack(spacing: 16) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.Colors.roastAccent.opacity(0.7))
                        Slider(value: $roastGridScale, in: 0.5...2.0, step: 0.1)
                            .tint(AppTheme.Colors.roastAccent)
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.Colors.roastAccent.opacity(0.7))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.Colors.surfaceElevated)
                            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    ScrollView {
                        LazyVGrid(columns: roastColumns, spacing: 10) {
                            ForEach(roastTargets) { target in
                                NavigationLink(destination: RoastTargetDetailView(target: target)) {
                                    RoastTargetGridCard(target: target, scale: CGFloat(roastGridScale))
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        roastTargetToDelete = target
                                        showingDeleteRoastAlert = true
                                    } label: {
                                        Label("Delete Target", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .animation(.easeOut(duration: 0.2), value: roastGridScale)
                    }
                    .scrollContentBackground(.hidden)
                }
            } else {
                List {
                    // Roast target list
                    ForEach(roastTargets) { target in
                        NavigationLink(destination: RoastTargetDetailView(target: target)) {
                            RoastTargetListRow(target: target)
                        }
                    }
                    .onDelete(perform: deleteRoastTargets)
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func deleteRoastTargets(at offsets: IndexSet) {
        let targets = roastTargets
        for index in offsets {
            guard index < targets.count else { continue }
            modelContext.delete(targets[index])
        }
        try? modelContext.save()
    }

    
    var filteredJokes: [Joke] {
        // Return cached result if available and no refresh needed
        if !needsFilterRefresh && !cachedFilteredJokes.isEmpty {
            return cachedFilteredJokes
        }
        
        // Start with base jokes depending on selected filter
        let base: [Joke]
        if showRecentlyAdded {
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            base = jokes.filter { $0.dateCreated >= sevenDaysAgo }
        } else if let folder = selectedFolder {
            let folderId = folder.id
            base = jokes.filter { $0.folder?.id == folderId }
        } else {
            base = jokes
        }
        
        // Exclude trashed jokes
        let active = base.filter { !$0.isDeleted }
        
        // Apply search filter if needed - use debounced text
        let trimmed = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [Joke]
        if trimmed.isEmpty {
            filtered = active
        } else {
            let lower = trimmed.lowercased()
            filtered = active.filter { matchesSearch($0, lower: lower) }
        }
        
        // Sort by dateCreated descending (newest first)
        return filtered.sorted { $0.dateCreated > $1.dateCreated }
    }
    
    var body: some View {
        NavigationStack {
            mainContent
                .background(
                    (roastMode ? AppTheme.Colors.roastBackground : Color.clear)
                        .ignoresSafeArea()
                )
                .navigationTitle(roastMode ? "🔥 Roasts" : "Jokes")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: roastMode ? "Search targets" : "Search jokes")
                .toolbarBackground(
                    roastMode ? AnyShapeStyle(AppTheme.Colors.roastSurface) : AnyShapeStyle(AppTheme.Colors.paperCream),
                    for: .navigationBar
                )
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(roastMode ? .dark : .light, for: .navigationBar)
                .onAppear { checkPendingVoiceMemoImports() }
                .toolbar { combinedToolbarContent }
                .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotos, matching: .images, preferredItemEncoding: .automatic)
                .onChange(of: selectedPhotos) { oldValue, newValue in
                    Task { await processSelectedPhotos(newValue) }
                }
                .modifier(JokesSheetsModifier(
                    showingAddJoke: $showingAddJoke,
                    showingScanner: $showingScanner,
                    showingCreateFolder: $showingCreateFolder,
                    showingAutoOrganize: $showingAutoOrganize,
                    showingAudioImport: $showingAudioImport,
                    showingTalkToText: $showingTalkToText,
                    showingFilePicker: $showingFilePicker,
                    showingAddRoastTarget: $showingAddRoastTarget,
                    showingMoveJokesSheet: $showingMoveJokesSheet,
                    showingReviewSheet: $showingReviewSheet,
                    selectedFolder: selectedFolder,
                    folders: folders,
                    folderPendingDeletion: $folderPendingDeletion,
                    reviewCandidates: reviewCandidates,
                    possibleDuplicates: possibleDuplicates,
                    unresolvedFragments: unresolvedImportFragments,
                    processScannedImages: processScannedImages,
                    processDocuments: processDocuments,
                    moveJokes: moveJokes,
                    deleteFolder: deleteFolder
                ))
                .sheet(isPresented: $showingImportHistory) {
                    ImportBatchHistoryView()
                }
                .modifier(JokesAlertsModifier(
                    showingExportAlert: $showingExportAlert,
                    showingImportSummary: $showingImportSummary,
                    showingDeleteFolderAlert: $showingDeleteFolderAlert,
                    showingDeleteRoastAlert: $showingDeleteRoastAlert,
                    showingMoveJokesSheet: $showingMoveJokesSheet,
                    exportedPDFURL: exportedPDFURL,
                    importSummary: importSummary,
                    folderPendingDeletion: $folderPendingDeletion,
                    roastTargetToDelete: $roastTargetToDelete,
                    jokes: jokes,
                    shareFile: shareFile,
                    removeJokesFromFolderAndDelete: removeJokesFromFolderAndDelete,
                    modelContext: modelContext
                ))
                .overlay { importOverlay }
                // Performance: Debounce search text updates
                .onChange(of: searchText) { _, newValue in
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            debouncedSearchText = newValue
                            needsFilterRefresh = true
                        }
                    }
                }
                // Invalidate cache when filter criteria change
                .onChange(of: selectedFolder) { _, _ in needsFilterRefresh = true }
                .onChange(of: showRecentlyAdded) { _, _ in needsFilterRefresh = true }
                .onChange(of: jokes.count) { _, _ in needsFilterRefresh = true }
        }
    }

    // MARK: - Extracted Body Subviews

    @ViewBuilder
    private var mainContent: some View {
        if roastMode {
            roastSection
        } else {
            VStack(spacing: 0) {
                // The Hits circle at the top
                theHitsButton
                
                folderChips

                Divider()
                if filteredJokes.isEmpty {
                    emptyState
                } else {
                    if viewMode == .grid {
                        VStack(spacing: 0) {
                            // Zoom slider
                            HStack(spacing: 16) {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.Colors.jokesAccent.opacity(0.7))
                                Slider(value: $jokesGridScale, in: 0.5...2.0, step: 0.1)
                                    .tint(AppTheme.Colors.jokesAccent)
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.Colors.jokesAccent.opacity(0.7))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.Colors.surfaceElevated)
                                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                            ScrollView {
                                LazyVGrid(columns: jokesColumns, spacing: 10) {
                                    ForEach(filteredJokes) { joke in
                                        NavigationLink(destination: JokeDetailView(joke: joke)) {
                                            JokeCardView(joke: joke, scale: CGFloat(jokesGridScale))
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                joke.moveToTrash()
                                            } label: {
                                                Label("Delete Joke", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .animation(.easeOut(duration: 0.2), value: jokesGridScale)
                            }
                            .scrollContentBackground(.hidden)
                        }
                    } else {
                        List {
                            ForEach(filteredJokes) { joke in
                                NavigationLink(destination: JokeDetailView(joke: joke)) {
                                    JokeRowView(joke: joke)
                                        .id(joke.id)
                                }
                                .listRowSeparator(.hidden)
                            }
                            .onDelete(perform: deleteJokes)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var combinedToolbarContent: some ToolbarContent {
        if roastMode {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        roastViewMode = roastViewMode == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: roastViewMode.icon)
                        .foregroundColor(AppTheme.Colors.roastAccent)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddRoastTarget = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        } else {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    Menu {
                        Button(action: { showingCreateFolder = true }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        Button(action: { showingAutoOrganize = true }) {
                            Label("Auto-Organize", systemImage: "wand.and.stars")
                        }
                        Button(action: { showingImportHistory = true }) {
                            Label("Import History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                        Button(action: { expandAllJokes.toggle() }) {
                            Label(expandAllJokes ? "Collapse Content" : "Expand Content", systemImage: expandAllJokes ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        }
                        Menu {
                            Button(action: exportJokesToPDF) {
                                Label("Export Jokes", systemImage: "doc.text")
                            }
                            Button(action: exportBrainstormToPDF) {
                                Label("Export Brainstorm", systemImage: "lightbulb")
                            }
                            Button(action: exportEverythingToPDF) {
                                Label("Export Everything", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Label("Export to PDF", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode = viewMode == .grid ? .list : .grid
                        }
                    } label: {
                        Image(systemName: viewMode.icon)
                            .foregroundColor(AppTheme.Colors.jokesAccent)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingAddJoke = true }) {
                        Label("Add Manually", systemImage: "square.and.pencil")
                    }
                    Button(action: { showingTalkToText = true }) {
                        Label("Talk-to-Text", systemImage: "mic.badge.plus")
                    }
                    Button(action: { showingScanner = true }) {
                        Label("Scan from Camera", systemImage: "camera")
                    }
                    Button(action: { showingImagePicker = true }) {
                        Label("Import Photos", systemImage: "photo.on.rectangle")
                    }
                    Button(action: { showingAudioImport = true }) {
                        Label("Import Voice Memos", systemImage: "waveform")
                    }
                    Button(action: { showingFilePicker = true }) {
                        Label("Import Files", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var importOverlay: some View {
        if isProcessingImages {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            ImportProgressCard(
                importFileCount: importFileCount,
                importFileIndex: importFileIndex,
                importStatusMessage: importStatusMessage,
                importedJokeNames: importedJokeNames
            )
        }
    }
    
    private func deleteJokes(at offsets: IndexSet) {
        let snapshot = filteredJokes
        for index in offsets {
            guard index < snapshot.count else { continue }
            // Soft-delete into trash
            snapshot[index].moveToTrash()
        }
    }
    
    private func moveJokes(from sourceFolder: JokeFolder, to destinationFolder: JokeFolder?) {
        let jokesInFolder = jokes.filter { $0.folder?.id == sourceFolder.id }
        for joke in jokesInFolder {
            joke.folder = destinationFolder
        }
        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to move jokes: \(error)")
        }
    }
    
    private func removeJokesFromFolderAndDelete(_ folder: JokeFolder) {
        let jokesInFolder = jokes.filter { $0.folder?.id == folder.id }
        for joke in jokesInFolder {
            joke.folder = nil
        }
        deleteFolder(folder)
    }
    
    private func deleteFolder(_ folder: JokeFolder) {
        // Move jokes out of the folder (set to nil) before deleting the folder
        let jokesInFolder = jokes.filter { $0.folder?.id == folder.id }
        for joke in jokesInFolder {
            joke.folder = nil
        }
        
        modelContext.delete(folder)
        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to delete folder: \(error)")
        }
    }
    
    private func processScannedImages(_ images: [UIImage]) {
        isProcessingImages = true
        importedJokeNames = []
        importStatusMessage = "Scanning \(images.count) image\(images.count == 1 ? "" : "s")..."
        importFileCount = images.count
        importFileIndex = 0
        
        Task {
            let extractionService = BitBuddyService.shared
            
            for image in images {
                await MainActor.run {
                    importFileIndex += 1
                    importStatusMessage = "Scanning image \(importFileIndex)/\(importFileCount)..."
                }
                
                do {
                    let text = try await TextRecognitionService.recognizeText(from: image)
                    
                    await MainActor.run {
                        importStatusMessage = "🤖 AI extracting jokes..."
                    }
                    
                    let extractedJokes = try await extractionService.extractJokes(from: text)
                    
                    await MainActor.run {
                        importStatusMessage = "Found \(extractedJokes.count) jokes, adding..."
                    }
                    
                    // Performance: Batch all joke insertions then save once
                    var jokesToCategorize: [(Joke, String)] = []
                    
                    for jokeText in extractedJokes {
                        let trimmed = jokeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.count >= 3 else { continue }
                        let title = String(trimmed.prefix(60))
                        
                        await MainActor.run {
                            let joke = Joke(content: trimmed, title: title, folder: self.selectedFolder)
                            self.modelContext.insert(joke)
                            jokesToCategorize.append((joke, trimmed))
                            self.importedJokeNames.append(title)
                            self.importStatusMessage = "Added \(self.importedJokeNames.count) jokes..."
                        }
                    }
                    
                    // Save all jokes in one batch
                    await MainActor.run {
                        try? self.modelContext.save()
                    }
                    
                    // Background categorization after batch save
                    for (joke, content) in jokesToCategorize {
                        Task.detached {
                            do {
                                let analysis = try await BitBuddyService.shared.analyzeJoke(content)
                                await MainActor.run {
                                    joke.category = analysis.category
                                    joke.tags = analysis.tags
                                    joke.difficulty = analysis.difficulty
                                    joke.humorRating = analysis.humorRating
                                    
                                    var folder = self.folders.first(where: { $0.name == analysis.category })
                                    if folder == nil {
                                        folder = JokeFolder(name: analysis.category)
                                        self.modelContext.insert(folder!)
                                    }
                                    joke.folder = folder
                                    // Note: Don't save after each categorization - let SwiftData auto-save
                                }
                            } catch { }
                        }
                    }
                } catch {
                    print("❌ SCANNER: Error: \(error)")
                }
            }
            await MainActor.run {
                // Final save after all categorizations
                try? self.modelContext.save()
                isProcessingImages = false
                importStatusMessage = ""
                importedJokeNames = []
                importFileCount = 0
                importFileIndex = 0
            }
        }
    }
    
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        isProcessingImages = true
        importedJokeNames = []
        importStatusMessage = "Loading \(items.count) photo\(items.count == 1 ? "" : "s")..."
        importFileCount = items.count
        importFileIndex = 0
        var added = 0
        var skipped = 0
        var duplicates: [String] = []
        let extractionService = BitBuddyService.shared
        
        for item in items {
            await MainActor.run {
                importFileIndex += 1
                importStatusMessage = "Scanning photo \(importFileIndex)/\(importFileCount)..."
            }
            
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                do {
                    let text = try await TextRecognitionService.recognizeText(from: image)
                    
                    await MainActor.run {
                        importStatusMessage = "🤖 AI extracting jokes..."
                    }
                    
                    let extractedJokes = try await extractionService.extractJokes(from: text)
                    
                    // Performance: Batch all insertions
                    var jokesToCategorize: [(Joke, String)] = []
                    
                    for jokeText in extractedJokes {
                        let trimmed = jokeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.count >= 3 else { continue }
                        let title = String(trimmed.prefix(60))
                        
                        if isLikelyDuplicate(trimmed, title: title) {
                            duplicates.append("\(title) — duplicate")
                            skipped += 1
                        } else {
                            await MainActor.run {
                                let joke = Joke(content: trimmed, title: title, folder: self.selectedFolder)
                                self.modelContext.insert(joke)
                                jokesToCategorize.append((joke, trimmed))
                                self.importedJokeNames.append(title)
                                self.importStatusMessage = "Added \(self.importedJokeNames.count) jokes..."
                            }
                            added += 1
                        }
                    }
                    
                    // Batch save all jokes from this photo
                    await MainActor.run {
                        try? self.modelContext.save()
                    }
                    
                    // Background categorization after save
                    for (joke, content) in jokesToCategorize {
                        Task.detached {
                            do {
                                let analysis = try await BitBuddyService.shared.analyzeJoke(content)
                                await MainActor.run {
                                    joke.category = analysis.category
                                    joke.tags = analysis.tags
                                    joke.difficulty = analysis.difficulty
                                    joke.humorRating = analysis.humorRating
                                    
                                    var folder = self.folders.first(where: { $0.name == analysis.category })
                                    if folder == nil {
                                        folder = JokeFolder(name: analysis.category)
                                        self.modelContext.insert(folder!)
                                    }
                                    joke.folder = folder
                                }
                            } catch { }
                        }
                    }
                } catch {
                    print("❌ PHOTOS: Error: \(error)")
                }
            }
        }
        await MainActor.run {
            // Final save for any remaining categorizations
            try? self.modelContext.save()
            importSummary = (added, skipped)
            showingImportSummary = true
            possibleDuplicates = duplicates
            selectedPhotos = []
            isProcessingImages = false
            importStatusMessage = ""
            importedJokeNames = []
            importFileCount = 0
            importFileIndex = 0
        }
    }
    
    private func processDocuments(_ urls: [URL]) {
        print("📂📂📂 IMPORT START: \(urls.count) files selected")
        isProcessingImages = true
        importedJokeNames = []
        importStatusMessage = "Starting import..."
        importFileCount = urls.count
        importFileIndex = 0
        
        Task {
            var totalAdded = 0
            var skipped = 0
            var duplicates: [String] = []
            
            for url in urls {
                await MainActor.run {
                    importFileIndex += 1
                    importStatusMessage = "Reading \(url.lastPathComponent)..."
                }
                
                print("📂 IMPORT: Processing \(url.lastPathComponent)")
                
                do {
                    let batch = try await FileImportService.shared.importBatch(from: url)
                    let persistedBatch = ImportBatch(
                        sourceFileName: batch.sourceFileName,
                        importTimestamp: batch.importTimestamp,
                        totalSegments: batch.stats.totalSegments,
                        totalImportedRecords: batch.stats.totalImportedRecords,
                        unresolvedFragmentCount: batch.stats.unresolvedFragmentCount,
                        highConfidenceBoundaries: batch.stats.highConfidenceBoundaries,
                        mediumConfidenceBoundaries: batch.stats.mediumConfidenceBoundaries,
                        lowConfidenceBoundaries: batch.stats.lowConfidenceBoundaries
                    )
                    await MainActor.run {
                        self.modelContext.insert(persistedBatch)
                    }
                    var persistedUnresolvedForBatch: [UnresolvedImportFragment] = []
                     
                    await MainActor.run {
                        importStatusMessage = "Adding \(batch.importedRecords.count) imported items..."
                    }
                    
                    // Performance: Batch all insertions for this file
                    for record in batch.importedRecords.sorted(by: { $0.sourceOrder < $1.sourceOrder }) {
                        let combinedContent = [record.body, record.notes]
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .joined(separator: record.notes.isEmpty ? "" : "\n\nNotes:\n")
                        let content = combinedContent.isEmpty ? record.rawSourceText : combinedContent
                        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? String(content.prefix(60))
                            : record.title
                        
                        if isLikelyDuplicate(content, title: title) {
                            duplicates.append("\(title) — duplicate")
                            skipped += 1
                            continue
                        }
                        
                        await MainActor.run {
                            let joke = Joke(content: content, title: title, folder: self.selectedFolder)
                            joke.tags = record.tags
                            joke.category = record.tags.first
                            self.modelContext.insert(joke)
                            
                            let metadata = ImportedJokeMetadata(
                                jokeID: joke.id,
                                title: record.title,
                                rawSourceText: record.rawSourceText,
                                notes: record.notes,
                                confidence: record.confidence.rawValue,
                                sourceOrder: record.sourceOrder,
                                sourcePage: record.sourcePage,
                                tags: record.tags,
                                parsingFlagsJSON: encodeParsingFlags(record.parsingFlags),
                                sourceFilename: record.sourceFilename,
                                importTimestamp: record.importTimestamp,
                                batch: persistedBatch
                            )
                            self.modelContext.insert(metadata)
                            
                            self.importedJokeNames.append(title)
                            self.importStatusMessage = "Added \(self.importedJokeNames.count) jokes..."
                        }
                        totalAdded += 1
                    }
                    
                    for unresolved in batch.unresolvedFragments where !unresolved.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let title = unresolved.titleCandidate ?? String(unresolved.text.prefix(40))
                        if isLikelyDuplicate(unresolved.text, title: title) {
                            skipped += 1
                            continue
                        }
                        await MainActor.run {
                            let joke = Joke(content: unresolved.text, title: title, folder: self.selectedFolder)
                            joke.tags = unresolved.tags
                            self.modelContext.insert(joke)
                            
                            let metadata = ImportedJokeMetadata(
                                jokeID: joke.id,
                                title: title,
                                rawSourceText: unresolved.text,
                                notes: unresolved.normalizedText,
                                confidence: unresolved.confidence.rawValue,
                                sourceOrder: unresolved.sourceLocation.orderIndex,
                                sourcePage: unresolved.sourceLocation.pageNumber,
                                tags: unresolved.tags,
                                parsingFlagsJSON: encodeParsingFlags(unresolved.parsingFlags),
                                sourceFilename: unresolved.sourceLocation.fileName,
                                importTimestamp: Date(),
                                batch: persistedBatch
                            )
                            self.modelContext.insert(metadata)
                            
                            let unresolvedModel = UnresolvedImportFragment(
                                text: unresolved.text,
                                normalizedText: unresolved.normalizedText,
                                kind: unresolved.kind.rawValue,
                                confidence: unresolved.confidence.rawValue,
                                sourceOrder: unresolved.sourceLocation.orderIndex,
                                sourcePage: unresolved.sourceLocation.pageNumber,
                                sourceFilename: unresolved.sourceLocation.fileName,
                                titleCandidate: unresolved.titleCandidate,
                                tags: unresolved.tags,
                                parsingFlagsJSON: encodeParsingFlags(unresolved.parsingFlags),
                                createdAt: Date(),
                                isResolved: false,
                                batch: persistedBatch
                            )
                            self.modelContext.insert(unresolvedModel)
                            persistedUnresolvedForBatch.append(unresolvedModel)
                            
                            self.importedJokeNames.append(title)
                        }
                        totalAdded += 1
                    }
                    
                    // Performance: Save all records for this file in one batch
                    await MainActor.run {
                        try? self.modelContext.save()
                        unresolvedImportFragments.append(contentsOf: persistedUnresolvedForBatch)
                        if !persistedUnresolvedForBatch.isEmpty {
                            showingReviewSheet = true
                        }
                    }
                } catch {
                    print("❌ IMPORT: Local batch import failed for \(url.lastPathComponent): \(error)")
                    let rawText = await readTextFromFile(url: url)
                    if let text = rawText {
                        await processLegacyTextImport(text, totalAdded: &totalAdded, skipped: &skipped, duplicates: &duplicates)
                    }
                }
            }
            
            await MainActor.run {
                self.importStatusMessage = ""
                self.isProcessingImages = false
                self.importSummary = (totalAdded, skipped)
                self.showingImportSummary = true
                self.possibleDuplicates = duplicates
                self.importedJokeNames = []
                self.importFileCount = 0
                self.importFileIndex = 0
                print("🏁 IMPORT DONE: Added \(totalAdded), skipped \(skipped)")
            }
        }
    }
    
    // MARK: - New PDF/AI Pipeline Methods

    private func processLegacyTextImport(_ text: String, totalAdded: inout Int, skipped: inout Int, duplicates: inout [String]) async {
        var jokes: [String] = []
        do {
            jokes = try await BitBuddyService.shared.extractJokes(from: text)
        } catch {
            jokes = basicSplitJokes(from: text)
        }
        
        if jokes.isEmpty {
            jokes = [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        
        for jokeText in jokes {
            let trimmed = jokeText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }
            
            let title = String(trimmed.prefix(60))
            
            if isLikelyDuplicate(trimmed, title: title) {
                duplicates.append("\(title) — duplicate")
                skipped += 1
                continue
            }
            
            await MainActor.run {
                let joke = Joke(content: trimmed, title: title, folder: self.selectedFolder)
                self.modelContext.insert(joke)
                try? self.modelContext.save()
                totalAdded += 1
                importedJokeNames.append(title)
            }
        }
    }

    /// Read text from any file type
    private func readTextFromFile(url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        print("📖 READ: \(url.lastPathComponent) ext=\(ext)")
        
        // PDF
        if ext == "pdf" {
            var allText = ""
            await processPDFToText(url: url) { pageText in
                allText += pageText + "\n\n"
            }
            if !allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("📖 READ: PDF → \(allText.count) chars")
                return allText
            }
            return nil
        }
        
        // Word docs
        if ["doc", "docx"].contains(ext) {
            if let attrStr = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                print("📖 READ: DOC → \(attrStr.string.count) chars")
                return attrStr.string
            }
            return nil
        }
        
        // Images — OCR
        if ["jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp", "gif"].contains(ext) {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                let text = try? await TextRecognitionService.recognizeText(from: image)
                print("📖 READ: IMAGE → \(text?.count ?? 0) chars")
                return text
            }
            return nil
        }
        
        // Everything else — try as plain text
        if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            print("📖 READ: TEXT → \(text.count) chars")
            return text
        }
        
        // Last resort — try reading raw data as ascii
        if let data = try? Data(contentsOf: url) {
            if let text = String(data: data, encoding: .ascii), !text.isEmpty {
                print("📖 READ: ASCII → \(text.count) chars")
                return text
            }
        }
        
        print("❌ READ: Could not read \(url.lastPathComponent)")
        return nil
    }
    
    /// Basic joke splitting when AI is unavailable
    private func basicSplitJokes(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try splitting by numbered list (1. 2. 3.)
        let numberedPattern = #"(?:^|\n)\s*\d+[\.\)]\s+"#
        if let regex = try? NSRegularExpression(pattern: numberedPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            let matches = regex.matches(in: trimmed, options: [], range: range)
            if matches.count >= 2 {
                var jokes: [String] = []
                var lastEnd = trimmed.startIndex
                for (i, match) in matches.enumerated() {
                    if let r = Range(match.range, in: trimmed) {
                        if i > 0 {
                            let joke = String(trimmed[lastEnd..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if joke.count >= 3 { jokes.append(joke) }
                        }
                        lastEnd = r.upperBound
                    }
                }
                let last = String(trimmed[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if last.count >= 3 { jokes.append(last) }
                if !jokes.isEmpty { return jokes }
            }
        }
        
        // Try splitting by blank lines
        let lines = trimmed.components(separatedBy: "\n")
        var jokes: [String] = []
        var current = ""
        for line in lines {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty {
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    jokes.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
            } else {
                current += (current.isEmpty ? "" : "\n") + l
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            jokes.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if jokes.count >= 2 { return jokes }
        
        // Try splitting by single newlines
        let singleLines = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 3 }
        if singleLines.count >= 2 { return singleLines }
        
        // Return whole text as one joke
        return trimmed.isEmpty ? [] : [trimmed]
    }
    
    /// Extract text from all PDF pages
    private func processPDFToText(url: URL, onPageText: @escaping (String) -> Void) async {
        guard let document = CGPDFDocument(url as CFURL) else {
            print("❌ PDF: Failed to load \(url.lastPathComponent)")
            return
        }
        
        let maxDim: CGFloat = 1800
        let pageCount = document.numberOfPages
        await MainActor.run {
            processingTotal = pageCount
            processingCurrent = 0
        }
        
        for pageNum in 1...pageCount {
            guard let page = document.page(at: pageNum) else { continue }
            let media = page.getBoxRect(.mediaBox)
            let scale = min(maxDim / max(media.width, media.height), 2.0)
            let renderSize = CGSize(width: media.width * scale, height: media.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: renderSize))
                ctx.cgContext.translateBy(x: 0, y: renderSize.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                ctx.cgContext.drawPDFPage(page)
            }
            do {
                let text = try await TextRecognitionService.recognizeText(from: image)
                onPageText(text)
                print("📄 PDF: Page \(pageNum)/\(pageCount) → \(text.count) chars")
            } catch {
                print("❌ PDF: OCR failed on page \(pageNum): \(error)")
            }
            await MainActor.run { processingCurrent += 1 }
            await Task.yield()
        }
    }
    
    private func exportJokesToPDF() {
        let jokesToExport: [Joke]
        if selectedFolder != nil {
            jokesToExport = filteredJokes
        } else {
            jokesToExport = jokes.filter { !$0.isDeleted }
        }
        if let url = PDFExportService.exportJokesToPDF(jokes: jokesToExport) {
            exportedPDFURL = url
            showingExportAlert = true
        }
    }
    
    private func exportBrainstormToPDF() {
        if let url = PDFExportService.exportBrainstormToPDF(ideas: brainstormIdeas) {
            exportedPDFURL = url
            showingExportAlert = true
        }
    }
    
    private func exportEverythingToPDF() {
        let jokesToExport = jokes.filter { !$0.isDeleted }
        if let url = PDFExportService.exportEverythingToPDF(jokes: jokesToExport, ideas: brainstormIdeas) {
            exportedPDFURL = url
            showingExportAlert = true
        }
    }
    
    private func shareFile(_ url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            // Required for iPad — set popover source to prevent crash
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func isLikelyDuplicate(_ content: String, title: String?) -> Bool {
        let newKey = content.normalizedPrefix()
        // Check against existing jokes in current filtered set and full list
        if jokes.contains(where: { $0.content.normalizedPrefix() == newKey }) { return true }
        if let title = title, !title.isEmpty {
            let t = title.lowercased().trimmingCharacters(in: .whitespaces)
            if jokes.contains(where: { $0.title.lowercased().trimmingCharacters(in: .whitespaces) == t }) { return true }
        }
        return false
    }
    
    private func checkPendingVoiceMemoImports() {
        let sharedDefaults = UserDefaults(suiteName: "group.com.taylordrew.thebitbinder")
        guard let pendingImports = sharedDefaults?.array(forKey: "pendingVoiceMemoImports") as? [[String: String]],
              !pendingImports.isEmpty else { return }
        
        var importedCount = 0
        for importData in pendingImports {
            guard let transcription = importData["transcription"],
                  !transcription.isEmpty else { continue }
            
            _ = importData["filename"] ?? "Voice Memo"
            let title = AudioTranscriptionService.generateTitle(from: transcription)
            
            // Check for duplicates
            if !isLikelyDuplicate(transcription, title: title) {
                let joke = Joke(content: transcription, title: title, folder: selectedFolder)
                modelContext.insert(joke)
                importedCount += 1
            }
        }
        
        // Clear pending imports
        sharedDefaults?.removeObject(forKey: "pendingVoiceMemoImports")
        sharedDefaults?.synchronize()
        
        if importedCount > 0 {
            try? modelContext.save()
            importSummary = (importedCount, 0)
            showingImportSummary = true
        }
    }
    
    private func encodeParsingFlags(_ flags: ImportParsingFlags) -> String {
        (try? String(data: JSONEncoder().encode(flags), encoding: .utf8)) ?? "{}"
    }
}

private extension JokesView {
    func matchesSearch(_ joke: Joke, lower: String) -> Bool {
        let title = joke.title.lowercased()
        if title.contains(lower) { return true }
        let content = joke.content.lowercased()
        return content.contains(lower)
    }
}

struct FolderChip: View {
    let name: String
    var icon: String = "folder.fill"
    let isSelected: Bool
    let action: () -> Void

    private let accent = AppTheme.Colors.jokesAccent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                }
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .serif))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Capsule().fill(accent) : Capsule().fill(AppTheme.Colors.paperAged))
            .foregroundColor(isSelected ? .white : AppTheme.Colors.textSecondary)
        }
        .buttonStyle(ChipStyle())
    }
}

struct JokeRowView: View {
    let joke: Joke
    @AppStorage("expandAllJokes") private var expandAllJokes = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("•")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.Colors.jokesAccent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(joke.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.Colors.inkBlack)
                    .lineLimit(1)

                Text(joke.content)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(expandAllJokes ? nil : 2)

                HStack(spacing: 8) {
                    if let folder = joke.folder {
                        Text(folder.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.Colors.jokesAccent)
                    }
                    Spacer()
                    Text(joke.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

struct RoastTargetCard: View {
    let target: RoastTarget

    var body: some View {
        VStack(spacing: 14) {
            // Avatar
            Group {
                if let data = target.photoData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.Colors.roastAccent.opacity(0.5), lineWidth: 1.5))
                } else {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.roastAccent.opacity(0.18))
                            .frame(width: 58, height: 58)
                        Text(target.name.prefix(1).uppercased())
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundColor(AppTheme.Colors.roastAccent)
                    }
                }
            }

            // Name + count
            VStack(spacing: 3) {
                Text(target.name)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))
            }

            // Flame meter
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < min(target.jokeCount, 5) ? "flame.fill" : "flame")
                        .font(.system(size: 9))
                        .foregroundColor(i < min(target.jokeCount, 5) ? AppTheme.Colors.roastAccent : Color.white.opacity(0.20))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.Colors.roastCard))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

// MARK: - View Mode

enum JokesViewMode: String, CaseIterable {
    case list = "List"
    case grid = "Grid"
    
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

// MARK: - Grid Card View

struct JokeCardView: View {
    let joke: Joke
    var scale: CGFloat = 1.0
    @AppStorage("expandAllJokes") private var expandAllJokes = false

    private var titleSize: CGFloat { max(11, 17 * scale) }
    private var bodySize: CGFloat  { max(9,  15 * scale) }
    private var metaSize: CGFloat  { max(8,  11 * scale) }
    private var cardMinHeight: CGFloat { max(100, 180 * scale) }

    var body: some View {
        VStack(alignment: .leading, spacing: max(4, 12 * scale)) {
            // Title
            Text(joke.title)
                .font(.system(size: titleSize, weight: .bold, design: .serif))
                .foregroundColor(AppTheme.Colors.inkBlack)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Content preview
            Text(joke.content)
                .font(.system(size: bodySize))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .lineLimit(expandAllJokes ? nil : max(2, Int(5 * scale)))
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // Footer
            HStack(spacing: 8) {
                if let folder = joke.folder {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: max(7, 9 * scale)))
                        Text(folder.name)
                            .font(.system(size: metaSize, weight: .medium))
                    }
                    .foregroundColor(AppTheme.Colors.jokesAccent)
                    .padding(.horizontal, max(4, 8 * scale))
                    .padding(.vertical, max(2, 4 * scale))
                    .background(Capsule().fill(AppTheme.Colors.jokesAccent.opacity(0.1)))
                }
                Spacer()
                Text(joke.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: metaSize))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
        }
        .padding(max(8, 16 * scale))
        .frame(minHeight: cardMinHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.Colors.surfaceElevated))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

// MARK: - Roast Target List Row

struct RoastTargetGridCard: View {
    let target: RoastTarget
    var scale: CGFloat = 1.0
    private let accentColor = AppTheme.Colors.roastAccent

    private var avatarSize: CGFloat { max(40, 70 * scale) }
    private var initialFontSize: CGFloat { max(16, 28 * scale) }
    private var nameFontSize: CGFloat { max(10, 15 * scale) }
    private var badgeFontSize: CGFloat { max(8, 12 * scale) }
    private var iconSize: CGFloat { max(6, 10 * scale) }
    private var verticalPadding: CGFloat { max(12, 18 * scale) }

    var body: some View {
        VStack(spacing: max(8, 12 * scale)) {
            // Avatar
            if let photoData = target.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(accentColor.opacity(0.5), lineWidth: 2))
            } else {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: avatarSize, height: avatarSize)
                    Text(target.name.prefix(1).uppercased())
                        .font(.system(size: initialFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                }
            }

            // Name
            Text(target.name)
                .font(.system(size: nameFontSize, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Joke count badge
            HStack(spacing: max(3, 4 * scale)) {
                Image(systemName: "flame.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(accentColor)
                Text("\(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s")")
                    .font(.system(size: badgeFontSize, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accentColor.opacity(0.15), lineWidth: 1)
        )
    }
}

struct RoastTargetListRow: View {
    let target: RoastTarget
    private let accentColor = AppTheme.Colors.roastAccent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Avatar
            if let photoData = target.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(accentColor.opacity(0.5), lineWidth: 1.5))
            } else {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Text(target.name.prefix(1).uppercased())
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                }
            }

            // Target info
            VStack(alignment: .leading, spacing: 4) {
                Text(target.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)
                    Text("\(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}
