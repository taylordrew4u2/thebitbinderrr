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
    
    // Smart import review
    @State private var smartImportResult: ImportPipelineResult?
    @State private var showingSmartImportReview = false
    
    // Batch select/delete mode
    @State private var isSelectMode = false
    @State private var selectedJokeIDs: Set<UUID> = []
    
    // Performance: Debounced search and cached filtered results
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var cachedFilteredJokes: [Joke] = []
    @State private var needsFilterRefresh = true

    // MARK: - The Hits Button
    
    // NOTE: The Hits is now integrated into the filter chips row
    // This computed property returns the count for the chips
    private var hitsCount: Int {
        jokes.filter { $0.isHit && !$0.isDeleted }.count
    }
    
    // State for showing The Hits filter
    @State private var showingHitsFilter = false


    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // The Hits chip (prominent, first position)
                TheHitsChip(
                    count: hitsCount,
                    isSelected: showingHitsFilter,
                    roastMode: roastMode,
                    action: {
                        showingHitsFilter.toggle()
                        if showingHitsFilter {
                            selectedFolder = nil
                            showRecentlyAdded = false
                        }
                    }
                )
                
                // Divider
                Rectangle()
                    .fill(roastMode ? Color.white.opacity(0.15) : AppTheme.Colors.divider)
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 4)
                
                // All Jokes
                FolderChip(
                    name: "All",
                    icon: "tray.full.fill",
                    isSelected: selectedFolder == nil && !showRecentlyAdded && !showingHitsFilter,
                    roastMode: roastMode,
                    action: {
                        selectedFolder = nil
                        showRecentlyAdded = false
                        showingHitsFilter = false
                    }
                )
                
                // Recently Added
                FolderChip(
                    name: "Recent",
                    icon: "clock.fill",
                    isSelected: showRecentlyAdded && !showingHitsFilter,
                    roastMode: roastMode,
                    action: {
                        showRecentlyAdded = true
                        selectedFolder = nil
                        showingHitsFilter = false
                    }
                )
                
                // Folder chips
                ForEach(folders) { folder in
                    FolderChip(
                        name: folder.name,
                        isSelected: selectedFolder?.id == folder.id && !showRecentlyAdded && !showingHitsFilter,
                        roastMode: roastMode,
                        action: {
                            selectedFolder = folder
                            showRecentlyAdded = false
                            showingHitsFilter = false
                        }
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
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(roastMode ? AppTheme.Colors.roastSurface.opacity(0.5) : AppTheme.Colors.paperAged.opacity(0.7))
    }

    @ViewBuilder
    private var emptyState: some View {
        JokesEmptyState(
            roastMode: roastMode,
            hasFilter: selectedFolder != nil || showRecentlyAdded || showingHitsFilter || !searchText.isEmpty,
            onAddJoke: { showingAddJoke = true }
        )
    }

    // MARK: - Roast Section

    @ViewBuilder
    private var roastSection: some View {
        if roastTargets.isEmpty {
            // Empty roast state
            BitBinderEmptyState(
                icon: "flame.fill",
                title: "No Roast Targets Yet",
                subtitle: "Add someone you want to roast and start writing jokes just for them",
                actionTitle: "Add First Target",
                action: { showingAddRoastTarget = true },
                roastMode: true,
                iconGradient: AppTheme.Colors.roastEmberGradient
            )
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
        if showingHitsFilter {
            // Show only hits
            base = jokes.filter { $0.isHit }
        } else if showRecentlyAdded {
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
        
        // Sort by dateModified descending (most recently touched first)
        return filtered.sorted { $0.dateModified > $1.dateModified }
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
                .bitBinderToolbar(roastMode: roastMode)
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
                .fullScreenCover(isPresented: $showingSmartImportReview) {
                    if let result = smartImportResult {
                        SmartImportReviewView(
                            importResult: result,
                            selectedFolder: selectedFolder,
                            onComplete: {
                                showingSmartImportReview = false
                                smartImportResult = nil
                            }
                        )
                    }
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
                .onChange(of: showingHitsFilter) { _, _ in needsFilterRefresh = true }
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
                // Filter chips (includes The Hits)
                folderChips

                Divider()
                    .opacity(0.5)
                
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
                                        if isSelectMode {
                                            jokeGridSelectableCard(joke: joke)
                                        } else {
                                            NavigationLink(destination: JokeDetailView(joke: joke)) {
                                                JokeCardView(joke: joke, scale: CGFloat(jokesGridScale), roastMode: roastMode)
                                            }
                                            .aspectRatio(1, contentMode: .fit)
                                            .contextMenu {
                                                if joke.isHit {
                                                    Button {
                                                        joke.isHit = false
                                                        joke.dateModified = Date()
                                                    } label: {
                                                        Label("Remove from Hits", systemImage: "star.slash")
                                                    }
                                                } else {
                                                    Button {
                                                        joke.isHit = true
                                                        joke.dateModified = Date()
                                                    } label: {
                                                        Label("Add to Hits", systemImage: "star.fill")
                                                    }
                                                }
                                                
                                                Divider()
                                                
                                                Button(role: .destructive) {
                                                    joke.moveToTrash()
                                                } label: {
                                                    Label("Move to Trash", systemImage: "trash")
                                                }
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
                                if isSelectMode {
                                    jokeListSelectableRow(joke: joke)
                                } else {
                                    NavigationLink(destination: JokeDetailView(joke: joke)) {
                                        JokeRowView(joke: joke, roastMode: roastMode)
                                            .id(joke.id)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            joke.moveToTrash()
                                        } label: {
                                            Label("Trash", systemImage: "trash")
                                        }
                                        
                                        Button {
                                            joke.isHit.toggle()
                                            joke.dateModified = Date()
                                        } label: {
                                            Label(joke.isHit ? "Remove Hit" : "Add Hit", systemImage: joke.isHit ? "star.slash" : "star.fill")
                                        }
                                        .tint(AppTheme.Colors.hitsGold)
                                    }
                                }
                            }
                            .onDelete(perform: deleteJokes)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(roastMode ? AppTheme.Colors.roastBackground : Color.clear)
                    }
                }
                
                // Batch action bar
                if isSelectMode {
                    batchActionBar
                }
            }
        }
    }
    
    // MARK: - Batch Select Mode Views
    
    @ViewBuilder
    private func jokeGridSelectableCard(joke: Joke) -> some View {
        let isSelected = selectedJokeIDs.contains(joke.id)
        Button {
            toggleSelection(joke)
        } label: {
            ZStack(alignment: .topTrailing) {
                JokeCardView(joke: joke, scale: CGFloat(jokesGridScale))
                    .opacity(isSelected ? 0.7 : 1.0)
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func jokeListSelectableRow(joke: Joke) -> some View {
        let isSelected = selectedJokeIDs.contains(joke.id)
        Button {
            toggleSelection(joke)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                
                JokeRowView(joke: joke)
            }
        }
        .listRowSeparator(.hidden)
        .buttonStyle(.plain)
    }
    
    private var batchActionBar: some View {
        HStack(spacing: 16) {
            Button {
                selectedJokeIDs = Set(filteredJokes.map(\.id))
            } label: {
                Text("Select All")
                    .font(.subheadline)
            }
            
            Spacer()
            
            Text("\(selectedJokeIDs.count) selected")
                .font(.subheadline.bold())
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Spacer()
            
            Button(role: .destructive) {
                batchTrashSelected()
            } label: {
                Label("Trash", systemImage: "trash")
                    .font(.subheadline.bold())
            }
            .disabled(selectedJokeIDs.isEmpty)
            .tint(.red)
            
            Button {
                isSelectMode = false
                selectedJokeIDs.removeAll()
            } label: {
                Text("Done")
                    .font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.surfaceElevated.shadow(.drop(radius: 4, y: -2)))
    }
    
    private func toggleSelection(_ joke: Joke) {
        if selectedJokeIDs.contains(joke.id) {
            selectedJokeIDs.remove(joke.id)
        } else {
            selectedJokeIDs.insert(joke.id)
        }
    }
    
    private func batchTrashSelected() {
        for joke in jokes where selectedJokeIDs.contains(joke.id) {
            joke.moveToTrash()
        }
        selectedJokeIDs.removeAll()
        isSelectMode = false
        try? modelContext.save()
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
                        Divider()
                        Button(action: {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedJokeIDs.removeAll() }
                        }) {
                            Label(isSelectMode ? "Cancel Selection" : "Select Multiple", systemImage: isSelectMode ? "xmark.circle" : "checkmark.circle")
                        }
                        Divider()
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
        NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
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
                        importStatusMessage = "🤖 Extracting jokes..."
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
                        importStatusMessage = "🤖 Extracting jokes..."
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
        print("📂📂📂 SMART IMPORT START: \(urls.count) files selected")
        isProcessingImages = true
        importedJokeNames = []
        importStatusMessage = "Analyzing file..."
        importFileCount = urls.count
        importFileIndex = 0
        
        Task {
            // For multi-file imports, we combine results from all files
            var combinedAutoSaved: [ImportedJoke] = []
            var combinedReview: [ImportedJoke] = []
            var combinedRejected: [LayoutBlock] = []
            var sourceFile = ""
            var anyLocalFallback = false
            var providersUsed = Set<String>()
            
            for url in urls {
                await MainActor.run {
                    importFileIndex += 1
                    importStatusMessage = "Analyzing \(url.lastPathComponent)..."
                }
                
                do {
                    let result = try await FileImportService.shared.importWithPipeline(from: url)
                    combinedAutoSaved.append(contentsOf: result.autoSavedJokes)
                    combinedReview.append(contentsOf: result.reviewQueueJokes)
                    combinedRejected.append(contentsOf: result.rejectedBlocks)
                    sourceFile = result.sourceFile
                    providersUsed.insert(result.providerUsed)
                    if result.usedLocalFallback { anyLocalFallback = true }
                    
                    await MainActor.run {
                        if result.usedLocalFallback {
                            importStatusMessage = "AI is asleep — using local extraction (may be rough)"
                        } else {
                            importStatusMessage = "Found \(result.autoSavedJokes.count + result.reviewQueueJokes.count) potential jokes..."
                        }
                    }
                } catch {
                    print("❌ IMPORT: Pipeline failed for \(url.lastPathComponent): \(error)")
                    // Fallback: try reading raw text and running through splitter
                    if let text = await readTextFromFile(url: url) {
                        let chunks = SmartTextSplitter.split(text)
                        for (i, chunk) in chunks.enumerated() {
                            let joke = ImportedJoke(
                                title: nil,
                                body: chunk,
                                rawSourceText: chunk,
                                tags: [],
                                confidence: .medium,
                                confidenceFactors: ConfidenceFactors(
                                    extractionQuality: 0.6,
                                    structuralCleanliness: 0.6,
                                    titleDetection: 0.3,
                                    boundaryClarity: 0.5,
                                    ocrConfidence: 1.0
                                ),
                                sourceMetadata: ImportSourceMetadata(
                                    fileName: url.lastPathComponent,
                                    pageNumber: 1,
                                    orderInPage: i,
                                    orderInFile: i,
                                    boundingBox: nil,
                                    importTimestamp: Date()
                                ),
                                validationResult: .requiresReview(reasons: ["Fallback extraction"]),
                                extractionMethod: .documentText
                            )
                            combinedReview.append(joke)
                        }
                        sourceFile = url.lastPathComponent
                        anyLocalFallback = true
                        providersUsed.insert("Local Extraction")
                    }
                }
            }
            
            let providerSummary: String = {
                let unique = Array(providersUsed)
                if unique.isEmpty { return "Unknown" }
                if unique.count == 1 { return unique[0] }
                return "Multiple"
            }()
            
            // Build combined result
            let combinedResult = ImportPipelineResult(
                sourceFile: sourceFile,
                autoSavedJokes: combinedAutoSaved,
                reviewQueueJokes: combinedReview,
                rejectedBlocks: combinedRejected,
                pipelineStats: PipelineStats(
                    totalPagesProcessed: 0,
                    totalLinesExtracted: 0,
                    totalBlocksCreated: combinedAutoSaved.count + combinedReview.count,
                    autoSavedCount: combinedAutoSaved.count,
                    reviewQueueCount: combinedReview.count,
                    rejectedCount: combinedRejected.count,
                    extractionMethod: .documentText,
                    processingTimeSeconds: 0,
                    averageConfidence: 0.7
                ),
                debugInfo: nil,
                providerUsed: providerSummary,
                usedLocalFallback: anyLocalFallback
            )
            
            await MainActor.run {
                self.isProcessingImages = false
                self.importStatusMessage = anyLocalFallback ? "AI is asleep — used local extraction" : ""
                self.importedJokeNames = []
                self.importFileCount = 0
                self.importFileIndex = 0
                
                let totalJokes = combinedAutoSaved.count + combinedReview.count
                if totalJokes > 0 {
                    // Show the Smart Import Review for ALL jokes — let user decide
                    self.smartImportResult = combinedResult
                    self.showingSmartImportReview = true
                } else {
                    // Nothing found
                    self.importSummary = (0, 0)
                    self.showingImportSummary = true
                }
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
        // Use App Group shared defaults for extension communication
        guard let sharedDefaults = UserDefaults(suiteName: "group.R44WG942GS.thebitbinder") else {
            print("⚠️ [VoiceMemo] App Group not available")
            return
        }
        guard let pendingImports = sharedDefaults.array(forKey: "pendingVoiceMemoImports") as? [[String: String]],
              !pendingImports.isEmpty else { return }
        
        print("📥 [VoiceMemo] Found \(pendingImports.count) pending voice memo imports")
        
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
        sharedDefaults.removeObject(forKey: "pendingVoiceMemoImports")
        sharedDefaults.synchronize()
        
        if importedCount > 0 {
            try? modelContext.save()
            importSummary = (importedCount, 0)
            showingImportSummary = true
            print("✅ [VoiceMemo] Imported \(importedCount) voice memos")
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

// MARK: - Roast Target Components
// Note: FolderChip, JokeRowView, JokeCardView, TheHitsChip, JokesViewMode
// are now in JokeComponents.swift

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

struct RoastTargetGridCard: View {
    let target: RoastTarget
    var scale: CGFloat = 1.0
    private let accentColor = AppTheme.Colors.roastAccent

    private var avatarSize: CGFloat { max(40, 70 * scale) }
    private var initialFontSize: CGFloat { max(14, 24 * scale) }
    private var nameFontSize: CGFloat { max(9, 13 * scale) }
    private var badgeFontSize: CGFloat { max(7, 10 * scale) }
    private var iconSize: CGFloat { max(6, 8 * scale) }
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
