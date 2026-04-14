//
//  RoastTargetDetailView.swift
//  thebitbinder
//
//  Shows a roast target's profile and all roast jokes for them.
//  Users can add, edit, reorder, and export roast jokes here.
//

import SwiftUI
import SwiftData
import PhotosUI

struct RoastTargetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showFullContent") private var showFullContent = true
    @AppStorage("roastSortOption") private var sortOption: RoastJokeSortOption = .newest
    @Bindable var target: RoastTarget
    
    // Query all non-deleted roast jokes for this target - SwiftData will auto-update the view
    @Query private var allRoastJokes: [RoastJoke]

    @State private var showingAddRoast = false
    @State private var editingJoke: RoastJoke?
    @State private var showingEditTarget = false
    @State private var showingTalkToText = false
    @State private var showingRecordingSheet = false
    @State private var showingDeleteTargetAlert = false
    @State private var searchText = ""
    @State private var persistenceError: String?
    @State private var showingPersistenceError = false
    @State private var showingRoastTrash = false
    @State private var showingExportSheet = false
    @State private var exportedFileURL: URL?
    
    // Filter state
    @State private var filterMode: RoastFilterMode = .all
    
    // Edit mode for drag-to-reorder
    @State private var isEditMode = false

    private let accentColor: Color = .blue
    
    enum RoastFilterMode: String, CaseIterable {
        case all = "All"
        case openers = "Openers"
        case killers = "Killers"
        case tested = "Tested"
        case untested = "Untested"
        
        var icon: String {
            switch self {
            case .all: return "flame.fill"
            case .openers: return "star.circle.fill"
            case .killers: return "star.fill"
            case .tested: return "checkmark.circle.fill"
            case .untested: return "circle.dashed"
            }
        }
    }
    
    /// Jokes for this target only, filtered from the @Query
    private var jokesForTarget: [RoastJoke] {
        guard target.isValid else { return [] }
        return allRoastJokes.filter { joke in
            !joke.isDeleted && joke.target?.id == target.id
        }
    }
    
    var displayedJokes: [RoastJoke] {
        guard target.isValid else { return [] }
        
        let baseJokes = jokesForTarget
        
        // First apply filter
        let filtered: [RoastJoke]
        switch filterMode {
        case .all:
            filtered = sortJokes(baseJokes, by: sortOption)
        case .openers:
            // Show opening roasts first, then their backups grouped underneath
            let openers = baseJokes.filter { $0.isOpeningRoast }
                .sorted { $0.displayOrder < $1.displayOrder }
            var result: [RoastJoke] = []
            for opener in openers {
                result.append(opener)
                // Add backups for this opener
                let backups = baseJokes.filter { 
                    $0.parentOpeningRoastID == opener.id 
                }.sorted { $0.displayOrder < $1.displayOrder }
                result.append(contentsOf: backups)
            }
            // Also add unassigned roasts (not openers, no parent)
            let unassigned = baseJokes.filter {
                !$0.isOpeningRoast && $0.parentOpeningRoastID == nil
            }
            if !unassigned.isEmpty {
                result.append(contentsOf: unassigned)
            }
            filtered = result
        case .killers:
            filtered = baseJokes.filter { $0.isKiller }.sorted { $0.dateCreated > $1.dateCreated }
        case .tested:
            filtered = baseJokes.filter { $0.isTested }.sorted { $0.performanceCount > $1.performanceCount }
        case .untested:
            filtered = baseJokes.filter { !$0.isTested }.sorted { $0.dateCreated > $1.dateCreated }
        }
        
        // Then apply search
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return filtered }
        return filtered.filter {
            $0.content.lowercased().contains(trimmed) ||
            $0.setup.lowercased().contains(trimmed) ||
            $0.punchline.lowercased().contains(trimmed)
        }
    }
    
    /// Sort jokes by the given option
    private func sortJokes(_ jokes: [RoastJoke], by option: RoastJokeSortOption) -> [RoastJoke] {
        switch option {
        case .custom:
            return jokes.sorted { $0.displayOrder < $1.displayOrder }
        case .newest:
            return jokes.sorted { $0.dateCreated > $1.dateCreated }
        case .oldest:
            return jokes.sorted { $0.dateCreated < $1.dateCreated }
        case .mostPerformed:
            return jokes.sorted { $0.performanceCount > $1.performanceCount }
        case .killers:
            // Killers first, then non-killers by date
            let killers = jokes.filter { $0.isKiller }.sorted { $0.dateCreated > $1.dateCreated }
            let nonKillers = jokes.filter { !$0.isKiller }.sorted { $0.dateCreated > $1.dateCreated }
            return killers + nonKillers
        case .relatability:
            return jokes.sorted { $0.relatabilityScore > $1.relatabilityScore }
        }
    }
    
    /// Safe access to target name to prevent crashes on invalidated models
    private var safeTargetName: String {
        target.isValid ? target.name : ""
    }
    
    /// Opening roasts for this target (for backup assignment)
    private var openingRoastsForTarget: [RoastJoke] {
        guard target.isValid else { return [] }
        return jokesForTarget.filter { $0.isOpeningRoast }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Target Header Card
            targetHeaderCard
            
            // Filter chips
            filterChips
            
            Divider()

            // Roast Jokes List
            if displayedJokes.isEmpty {
                emptyState
            } else {
                jokesList
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search roasts")
        .toolbar { toolbarContent }
        .alert("Delete \(safeTargetName)?", isPresented: $showingDeleteTargetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTarget()
            }
        } message: {
            Text("This will move \(safeTargetName) and all \(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s") to trash.")
        }
        .alert("Error", isPresented: $showingPersistenceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showingAddRoast) {
            AddRoastJokeView(target: target)
        }
        .sheet(item: $editingJoke) { joke in
            EditRoastJokeView(joke: joke)
        }
        .sheet(isPresented: $showingEditTarget) {
            EditRoastTargetView(target: target)
        }
        .sheet(isPresented: $showingTalkToText) {
            TalkToTextRoastView(target: target)
        }
        .sheet(isPresented: $showingRecordingSheet) {
            RecordRoastSetView(target: target)
        }
        .sheet(isPresented: $showingExportSheet) {
            RoastExportSheet(target: target, exportedURL: $exportedFileURL)
        }
        .navigationDestination(isPresented: $showingRoastTrash) {
            RoastJokeTrashView(target: target)
        }
    }
    
    // MARK: - View Components
    
    private var targetHeaderCard: some View {
        VStack(spacing: 12) {
            // Avatar
            AsyncAvatarView(
                photoData: target.photoData,
                size: 72,
                fallbackInitial: String(safeTargetName.prefix(1).uppercased()),
                accentColor: accentColor
            )
            .overlay(Circle().stroke(accentColor.opacity(0.5), lineWidth: 2))

            Text(safeTargetName)
                .font(.system(size: 20, weight: .bold))

            if !target.notes.isEmpty {
                Text(target.notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !target.traits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(target.traits, id: \.self) { trait in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(accentColor)
                            Text(trait)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }

            // Stats row
            HStack(spacing: 16) {
                StatBadge(
                    count: target.jokeCount,
                    label: "roast",
                    icon: "flame.fill",
                    color: accentColor
                )
                
                if target.killerCount > 0 {
                    StatBadge(
                        count: target.killerCount,
                        label: "killer",
                        icon: "star.fill",
                        color: .blue
                    )
                }
                
                if target.testedCount > 0 {
                    StatBadge(
                        count: target.testedCount,
                        label: "tested",
                        icon: "checkmark.circle.fill",
                        color: .blue
                    )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            accentColor.opacity(0.05)
        )
    }
    
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(RoastFilterMode.allCases, id: \.rawValue) { mode in
                    FilterChip(
                        title: mode.rawValue,
                        icon: mode.icon,
                        isSelected: filterMode == mode,
                        accentColor: accentColor
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterMode = mode
                        }
                    }
                }
                
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)
                
                // Sort menu
                Menu {
                    ForEach(RoastJokeSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            Label(option.rawValue, systemImage: option.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortOption.icon)
                        Text("Sort")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground).opacity(0.95))
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: filterMode == .all ? "flame" : filterMode.icon)
                .font(.system(size: 50))
                .foregroundColor(accentColor.opacity(0.4))
            
            if filterMode == .all {
                Text("No roasts yet")
                    .font(.title3.bold())
                
                Text("Start roasting \(safeTargetName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button {
                    showingAddRoast = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.headline)
                        Text("Write First Roast")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(accentColor)
                    .cornerRadius(12)
                }
                .padding(.top, 8)
            } else {
                Text("No \(filterMode.rawValue.lowercased()) roasts")
                    .font(.title3.bold())
                Text("Roasts will appear here once you mark them as \(filterMode.rawValue.lowercased())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var jokesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(displayedJokes) { joke in
                    DraggableRoastCard(
                        joke: joke,
                        showFullContent: showFullContent,
                        accentColor: accentColor,
                        isDragEnabled: sortOption == .custom,
                        onTap: {
                            editingJoke = joke
                        },
                        onToggleKiller: {
                            toggleKiller(joke)
                        },
                        onToggleTested: {
                            recordPerformance(joke)
                        },
                        onUndoPerformance: {
                            undoPerformance(joke)
                        },
                        onTrash: {
                            withAnimation(.easeOut(duration: 0.25)) {
                                trashJoke(joke)
                            }
                        },
                        onToggleOpening: {
                            toggleOpeningRoast(joke)
                        },
                        onAssignAsBackup: { parentID in
                            assignAsBackup(joke, to: parentID)
                        },
                        openingRoastsForTarget: openingRoastsForTarget.filter { $0.id != joke.id },
                        onDragStarted: {
                            startDragging(joke)
                        },
                        onDragEnded: { targetJoke in
                            endDragging(joke, onto: targetJoke)
                        },
                        allJokes: displayedJokes
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .trailing))
                    ))
                }
                
                // Quick add button at bottom
                Button {
                    showingAddRoast = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(accentColor.opacity(0.12))
                                .frame(width: 42, height: 42)
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                        
                        Text("Add another roast")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(accentColor)
                        
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Drag & Drop Helpers
    
    @State private var draggingJoke: RoastJoke?
    
    private func startDragging(_ joke: RoastJoke) {
        draggingJoke = joke
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func endDragging(_ sourceJoke: RoastJoke, onto targetJoke: RoastJoke?) {
        guard sortOption == .custom,
              let target = targetJoke,
              sourceJoke.id != target.id else {
            draggingJoke = nil
            return
        }
        
        var jokes = displayedJokes
        guard let sourceIndex = jokes.firstIndex(where: { $0.id == sourceJoke.id }),
              let targetIndex = jokes.firstIndex(where: { $0.id == target.id }) else {
            draggingJoke = nil
            return
        }
        
        // Move the joke
        let joke = jokes.remove(at: sourceIndex)
        jokes.insert(joke, at: targetIndex)
        
        // Update display orders
        for (index, j) in jokes.enumerated() {
            j.displayOrder = index
        }
        
        // Haptic feedback for successful drop
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        saveContext("drag reorder")
        draggingJoke = nil
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showingEditTarget = true
            } label: {
                Image(systemName: "pencil")
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingAddRoast = true
            } label: {
                Image(systemName: "plus")
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Section("View") {
                    Button(action: { showFullContent.toggle() }) {
                        Label(showFullContent ? "Compact View" : "Full Content", systemImage: showFullContent ? "list.bullet" : "text.justify.leading")
                    }
                    
                    if sortOption == .custom {
                        Button(action: { isEditMode.toggle() }) {
                            Label(isEditMode ? "Done Reordering" : "Reorder Roasts", systemImage: isEditMode ? "checkmark" : "line.3.horizontal")
                        }
                    }
                }
                
                Divider()
                
                Section("Other Ways to Add") {
                    Button(action: { showingTalkToText = true }) {
                        Label("Talk-to-Text", systemImage: "mic.badge.plus")
                    }
                    Button(action: { showingRecordingSheet = true }) {
                        Label("Record Set", systemImage: "record.circle")
                    }
                }
                
                Divider()
                
                Button(action: { showingExportSheet = true }) {
                    Label("Export Roasts", systemImage: "square.and.arrow.up")
                }
                
                Button { showingRoastTrash = true } label: {
                    Label("Trash", systemImage: "trash")
                }
                
                Divider()
                
                Button(role: .destructive, action: { showingDeleteTargetAlert = true }) {
                    Label("Delete Target", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    
    // MARK: - Actions
    
    private func deleteTarget() {
        target.moveToTrash()
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("⚠️ [RoastTargetDetailView] Failed to persist delete: \(error)")
            persistenceError = "Could not delete \(safeTargetName): \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }

    private func deleteRoasts(at offsets: IndexSet) {
        let jokes = displayedJokes
        for index in offsets {
            guard index < jokes.count else { continue }
            jokes[index].moveToTrash()
        }
        saveContext("roast soft-delete")
    }
    
    private func moveJokes(from source: IndexSet, to destination: Int) {
        var jokes = displayedJokes
        jokes.move(fromOffsets: source, toOffset: destination)
        // Update display order for all jokes
        for (index, joke) in jokes.enumerated() {
            joke.displayOrder = index
        }
        saveContext("reorder")
    }
    
    private func toggleKiller(_ joke: RoastJoke) {
        joke.isKiller.toggle()
        joke.dateModified = Date()
        saveContext("killer toggle")
    }
    
    private func recordPerformance(_ joke: RoastJoke) {
        joke.recordPerformance()
        saveContext("performance record")
    }
    
    private func undoPerformance(_ joke: RoastJoke) {
        joke.undoPerformance()
        saveContext("performance undo")
    }
    
    private func trashJoke(_ joke: RoastJoke) {
        joke.moveToTrash()
        saveContext("trash joke")
    }
    
    private func toggleOpeningRoast(_ joke: RoastJoke) {
        joke.isOpeningRoast.toggle()
        if joke.isOpeningRoast {
            // Clear parent if becoming an opening roast
            joke.parentOpeningRoastID = nil
        }
        joke.dateModified = Date()
        saveContext("opening roast toggle")
    }
    
    private func assignAsBackup(_ joke: RoastJoke, to parentID: UUID?) {
        joke.parentOpeningRoastID = parentID
        if parentID != nil {
            // Can't be an opening roast if it's a backup
            joke.isOpeningRoast = false
        }
        joke.dateModified = Date()
        saveContext("backup assignment")
    }
    
    private func saveContext(_ action: String) {
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [RoastTargetDetailView] Failed to persist \(action): \(error)")
            persistenceError = "Could not save changes: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let count: Int
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text("\(count) \(label)\(count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color)
        .clipShape(Capsule())
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(isSelected ? .white : accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? accentColor : accentColor.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Draggable Roast Card

struct DraggableRoastCard: View {
    let joke: RoastJoke
    var showFullContent: Bool = true
    let accentColor: Color
    var isDragEnabled: Bool = true
    var onTap: (() -> Void)? = nil
    var onToggleKiller: (() -> Void)? = nil
    var onToggleTested: (() -> Void)? = nil
    var onUndoPerformance: (() -> Void)? = nil
    var onTrash: (() -> Void)? = nil
    var onToggleOpening: (() -> Void)? = nil
    var onAssignAsBackup: ((UUID?) -> Void)? = nil
    var openingRoastsForTarget: [RoastJoke] = []
    var onDragStarted: (() -> Void)? = nil
    var onDragEnded: ((RoastJoke?) -> Void)? = nil
    var allJokes: [RoastJoke] = []
    
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var isPressed = false
    @State private var showDeleteConfirm = false
    @GestureState private var longPressActive = false
    
    // Swipe to delete state
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwipeDeleting = false
    @State private var isSwipeKiller = false
    private let swipeThreshold: CGFloat = -100
    private let deleteThreshold: CGFloat = -150
    private let killerThreshold: CGFloat = 100
    
    private let cardCornerRadius: CGFloat = 16
    
    var body: some View {
        ZStack {
            // Killer background (revealed on right swipe)
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .fill(Color.blue)
                    
                    HStack(spacing: 8) {
                        Image(systemName: joke.isKiller ? "star.slash.fill" : "star.fill")
                            .font(.system(size: 20, weight: .semibold))
                        if isSwipeKiller {
                            Text(joke.isKiller ? "Remove" : "Killer!")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundColor(.black.opacity(0.8))
                    .opacity(swipeOffset > 50 ? 1 : 0.7)
                    .scaleEffect(isSwipeKiller ? 1.1 : 1.0)
                }
                .frame(width: max(80, swipeOffset))
                Spacer()
            }
            .opacity(swipeOffset > 20 ? 1 : 0)
            
            // Delete background (revealed on left swipe)
            HStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .fill(Color.red)
                    
                    HStack(spacing: 8) {
                        Image(systemName: isSwipeDeleting ? "trash.fill" : "trash")
                            .font(.system(size: 20, weight: .semibold))
                        if isSwipeDeleting {
                            Text("Release")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .opacity(swipeOffset < swipeThreshold ? 1 : 0.7)
                    .scaleEffect(isSwipeDeleting ? 1.1 : 1.0)
                }
                .frame(width: max(80, -swipeOffset))
            }
            .opacity(swipeOffset < -20 ? 1 : 0)
            
            // Drop target indicator (shows when dragging)
            if isDragging {
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .strokeBorder(accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .frame(height: 80)
            }
            
            // Main card
            cardContent
                .background(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(
                            color: isDragging ? accentColor.opacity(0.3) : Color.black.opacity(isPressed ? 0.15 : 0.08),
                            radius: isDragging ? 20 : (isPressed ? 12 : 6),
                            x: 0,
                            y: isDragging ? 12 : (isPressed ? 6 : 2)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(
                            isDragging ? accentColor : (joke.isKiller ? Color.blue.opacity(0.4) : Color.clear),
                            lineWidth: isDragging ? 2 : 1
                        )
                )
                .scaleEffect(isDragging ? 1.03 : (isPressed ? 0.98 : 1.0))
                .rotationEffect(.degrees(isDragging ? Double(dragOffset.width / 30).clamped(to: -3...3) : 0))
                .offset(x: swipeOffset, y: dragOffset.height)
                .offset(dragOffset.height == 0 ? .zero : CGSize(width: dragOffset.width, height: 0))
                .zIndex(isDragging ? 100 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: swipeOffset)
                .gesture(swipeGesture)
                .simultaneousGesture(combinedGesture)
        }
        .padding(.horizontal, 16)
        .confirmationDialog("Delete Roast?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                onTrash?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This roast will be moved to trash.")
        }
    }
    
    // Swipe gesture for delete and killer
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isDragging else { return }
                
                // Horizontal swipe only
                if abs(value.translation.width) > abs(value.translation.height) {
                    swipeOffset = value.translation.width
                    
                    // Left swipe - delete threshold (only haptic when crossing into delete zone)
                    if swipeOffset < deleteThreshold && !isSwipeDeleting {
                        isSwipeDeleting = true
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    } else if swipeOffset > deleteThreshold && isSwipeDeleting {
                        isSwipeDeleting = false
                        // No haptic on retreat - too sensitive
                    }
                    
                    // Right swipe - killer threshold
                    if swipeOffset > killerThreshold && !isSwipeKiller {
                        isSwipeKiller = true
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    } else if swipeOffset < killerThreshold && isSwipeKiller {
                        isSwipeKiller = false
                        // No haptic on retreat - too sensitive
                    }
                }
            }
            .onEnded { value in
                if swipeOffset < deleteThreshold {
                    // Delete with animation
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    withAnimation(.easeOut(duration: 0.2)) {
                        swipeOffset = -500
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onTrash?()
                    }
                } else if swipeOffset > killerThreshold {
                    // Toggle killer with bounce animation
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        swipeOffset = 0
                        isSwipeKiller = false
                    }
                    
                    onToggleKiller?()
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        swipeOffset = 0
                        isSwipeDeleting = false
                        isSwipeKiller = false
                    }
                }
            }
    }
    
    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Drag handle (visible when drag is enabled)
            if isDragEnabled {
                VStack {
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 24)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            
            // Icon - tappable for killer toggle
            Button {
                onToggleKiller?()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(joke.isKiller ? Color.blue.opacity(0.2) : accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: joke.isKiller ? "star.fill" : "flame.fill")
                        .font(.system(size: 20))
                        .foregroundColor(joke.isKiller ? .blue : accentColor)
                }
            }
            .buttonStyle(.plain)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                if showFullContent {
                    Text(joke.content)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .lineLimit(4)
                } else {
                    Text(joke.content.components(separatedBy: .newlines).first ?? joke.content)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                
                // Badges row
                HStack(spacing: 6) {
                    // Opening roast badge
                    if joke.isOpeningRoast {
                        BadgePill(text: "OPENER", icon: "star.circle.fill", color: .blue)
                    } else if joke.parentOpeningRoastID != nil {
                        BadgePill(text: "BACKUP", icon: "arrow.turn.down.right", color: .blue)
                    }
                    
                    // Tested badge - tappable
                    if joke.isTested {
                        Button {
                            onToggleTested?()
                        } label: {
                            BadgePill(text: "\(joke.performanceCount)×", icon: "checkmark.circle.fill", color: .blue)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Relatability
                    if joke.relatabilityScore > 0 {
                        HStack(spacing: 1) {
                            ForEach(0..<5, id: \.self) { i in
                                Circle()
                                    .fill(i < joke.relatabilityScore ? Color.blue : Color.gray.opacity(0.2))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Text(joke.dateCreated, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer(minLength: 0)
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(14)
        .contentShape(Rectangle())
        .contextMenu {
            contextMenuContent
        }
    }
    
    private var combinedGesture: some Gesture {
        let tap = TapGesture()
            .onEnded {
                onTap?()
            }
        
        let longPress = LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                if isDragEnabled {
                    isDragging = true
                    onDragStarted?()
                }
            }
        
        let drag = DragGesture()
            .onChanged { value in
                guard isDragEnabled else { return }
                
                if !isDragging && abs(value.translation.height) > 10 {
                    isDragging = true
                    onDragStarted?()
                }
                
                if isDragging {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                guard isDragEnabled && isDragging else { return }
                
                // Find target joke based on drag position
                let targetJoke = findTargetJoke(for: value.translation)
                onDragEnded?(targetJoke)
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    dragOffset = .zero
                    isDragging = false
                }
            }
        
        let press = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isDragging {
                    isPressed = true
                }
            }
            .onEnded { _ in
                isPressed = false
            }
        
        return tap
            .simultaneously(with: longPress)
            .simultaneously(with: drag)
            .simultaneously(with: press)
    }
    
    private func findTargetJoke(for translation: CGSize) -> RoastJoke? {
        // Estimate row height and find target index
        let estimatedRowHeight: CGFloat = 100
        let indexOffset = Int(translation.height / estimatedRowHeight)
        
        guard let currentIndex = allJokes.firstIndex(where: { $0.id == joke.id }) else {
            return nil
        }
        
        let targetIndex = currentIndex + indexOffset
        guard targetIndex >= 0 && targetIndex < allJokes.count && targetIndex != currentIndex else {
            return nil
        }
        
        return allJokes[targetIndex]
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onToggleKiller?()
        } label: {
            Label(joke.isKiller ? "Remove Killer" : "Mark as Killer", systemImage: joke.isKiller ? "star.slash" : "star.fill")
        }
        
        Button {
            onToggleTested?()
        } label: {
            Label("Add Performance +1", systemImage: "checkmark.circle")
        }
        
        if joke.performanceCount > 0 {
            Button {
                onUndoPerformance?()
            } label: {
                Label("Undo Performance -1 (\(joke.performanceCount))", systemImage: "arrow.uturn.backward.circle")
            }
        }
        
        Divider()
        
        Button {
            onToggleOpening?()
        } label: {
            Label(joke.isOpeningRoast ? "Remove as Opener" : "Mark as Opening Roast", systemImage: joke.isOpeningRoast ? "star.circle" : "star.circle.fill")
        }
        
        if !joke.isOpeningRoast && !openingRoastsForTarget.isEmpty {
            Menu {
                Button {
                    onAssignAsBackup?(nil)
                } label: {
                    HStack {
                        Text("None (Unassigned)")
                        if joke.parentOpeningRoastID == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                ForEach(Array(openingRoastsForTarget.enumerated()), id: \.element.id) { index, opening in
                    Button {
                        onAssignAsBackup?(opening.id)
                    } label: {
                        HStack {
                            Text("Opener \(index + 1): \(opening.content.prefix(25))...")
                            if joke.parentOpeningRoastID == opening.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(joke.parentOpeningRoastID != nil ? "Change Backup Assignment" : "Assign as Backup For...", systemImage: "arrow.turn.down.right")
            }
        }
        
        Divider()
        
        Button {
            onTap?()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        
        Divider()
        
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}

// MARK: - Badge Pill

struct BadgePill: View {
    let text: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Double Extension

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Roast Joke Row (Legacy)

struct RoastJokeRow: View {
    let joke: RoastJoke
    var showFullContent: Bool = true
    let accentColor: Color
    var onToggleKiller: (() -> Void)? = nil
    var onToggleTested: (() -> Void)? = nil
    var onUndoPerformance: (() -> Void)? = nil
    var onQuickEdit: (() -> Void)? = nil
    var onAddStructure: (() -> Void)? = nil
    var onTrash: (() -> Void)? = nil
    var onToggleOpening: (() -> Void)? = nil
    var onAssignAsBackup: ((UUID?) -> Void)? = nil
    var openingRoastsForTarget: [RoastJoke] = []

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon with badges - tappable for killer toggle
            Button {
                onToggleKiller?()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(joke.isKiller ? Color.blue.opacity(0.2) : accentColor.opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: joke.isKiller ? "star.fill" : "flame.fill")
                            .font(.system(size: 18))
                            .foregroundColor(joke.isKiller ? .blue : accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // Main content
                if showFullContent {
                    Text(joke.content)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                } else {
                    Text(joke.content.components(separatedBy: .newlines).first ?? joke.content)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                // Metadata row
                HStack(spacing: 8) {
                    Text(joke.dateCreated, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    // Opening roast badge
                    if joke.isOpeningRoast {
                        HStack(spacing: 2) {
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                            Text("OPENER")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    } else if joke.parentOpeningRoastID != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 8))
                                .foregroundColor(.blue)
                            Text("BACKUP")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Tappable tested badge
                    if joke.isTested {
                        Button {
                            onToggleTested?()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                                Text("\(joke.performanceCount)x")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if joke.relatabilityScore > 0 {
                        HStack(spacing: 1) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: i < joke.relatabilityScore ? "person.fill" : "person")
                                    .font(.system(size: 7))
                                    .foregroundColor(i < joke.relatabilityScore ? .blue : .gray.opacity(0.3))
                            }
                        }
                    }
                    
                    if joke.hasStructure {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9))
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            // Quick action chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            // Quick actions context menu
            Button {
                onToggleKiller?()
            } label: {
                Label(joke.isKiller ? "Remove Killer" : "Mark as Killer", systemImage: joke.isKiller ? "star.slash" : "star.fill")
            }
            
            Button {
                onToggleTested?()
            } label: {
                Label("Add Performance +1", systemImage: "checkmark.circle")
            }
            
            if joke.performanceCount > 0 {
                Button {
                    onUndoPerformance?()
                } label: {
                    Label("Undo Performance -1 (\(joke.performanceCount))", systemImage: "arrow.uturn.backward.circle")
                }
            }
            
            Divider()
            
            // Opening roast / Backup section
            Button {
                onToggleOpening?()
            } label: {
                Label(joke.isOpeningRoast ? "Remove as Opener" : "Mark as Opening Roast", systemImage: joke.isOpeningRoast ? "star.circle" : "star.circle.fill")
            }
            
            // Backup assignment submenu (only if not an opening roast)
            if !joke.isOpeningRoast && !openingRoastsForTarget.isEmpty {
                Menu {
                    // None option
                    Button {
                        onAssignAsBackup?(nil)
                    } label: {
                        HStack {
                            Text("None (Unassigned)")
                            if joke.parentOpeningRoastID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Opening roast options
                    ForEach(Array(openingRoastsForTarget.enumerated()), id: \.element.id) { index, opening in
                        Button {
                            onAssignAsBackup?(opening.id)
                        } label: {
                            HStack {
                                Text("Opener \(index + 1): \(opening.content.prefix(30))...")
                                if joke.parentOpeningRoastID == opening.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(joke.parentOpeningRoastID != nil ? "Change Backup Assignment" : "Assign as Backup For...", systemImage: "arrow.turn.down.right")
                }
            }
            
            Divider()
            
            if !joke.hasStructure {
                Button {
                    onAddStructure?()
                } label: {
                    Label("Add Setup/Punchline", systemImage: "text.alignleft")
                }
            }
            
            Button {
                onQuickEdit?()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onTrash?()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}

// MARK: - Export Sheet

struct RoastExportSheet: View {
    let target: RoastTarget
    @Binding var exportedURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var exportFormat: ExportFormat = .text
    @State private var includeStructure = true
    @State private var includeNotes = true
    @State private var isExporting = false
    @State private var showShareSheet = false
    
    enum ExportFormat: String, CaseIterable {
        case text = "Plain Text"
        case pdf = "PDF"
        case markdown = "Markdown"
        
        var icon: String {
            switch self {
            case .text: return "doc.text"
            case .pdf: return "doc.richtext"
            case .markdown: return "text.badge.checkmark"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Label(format.rawValue, systemImage: format.icon)
                                .tag(format)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                
                Section("Include") {
                    Toggle("Joke Structure (Setup/Punchline)", isOn: $includeStructure)
                    Toggle("Performance Notes", isOn: $includeNotes)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.headline)
                        Text("\(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s") for \(target.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if target.killerCount > 0 {
                            Text("Including \(target.killerCount) killer\(target.killerCount == 1 ? "" : "s") ⭐️")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Export Roasts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        exportRoasts()
                    }
                    .disabled(isExporting)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
    
    private func exportRoasts() {
        isExporting = true
        
        Task {
            let url: URL?
            
            switch exportFormat {
            case .text:
                url = exportAsText()
            case .pdf:
                url = PDFExportService.exportRoastsToPDF(targets: [target], fileName: "Roasts_\(target.name)")
            case .markdown:
                url = exportAsMarkdown()
            }
            
            await MainActor.run {
                isExporting = false
                if let url = url {
                    exportedURL = url
                    showShareSheet = true
                }
            }
        }
    }
    
    private func exportAsText() -> URL? {
        var text = "ROASTS FOR \(target.name.uppercased())\n"
        text += String(repeating: "=", count: 40) + "\n\n"
        
        if !target.notes.isEmpty {
            text += "About: \(target.notes)\n\n"
        }
        
        if !target.traits.isEmpty {
            text += "Traits:\n"
            for trait in target.traits {
                text += "• \(trait)\n"
            }
            text += "\n"
        }
        
        text += String(repeating: "-", count: 40) + "\n\n"
        
        let allJokes = target.sortedJokes
        let openingRoasts = allJokes.filter { $0.isOpeningRoast }.sorted { $0.displayOrder < $1.displayOrder }
        let backupRoasts = allJokes.filter { !$0.isOpeningRoast && $0.parentOpeningRoastID != nil }
        let unassignedRoasts = allJokes.filter { !$0.isOpeningRoast && $0.parentOpeningRoastID == nil }
        
        var jokeIndex = 1
        
        // Opening roasts section
        if !openingRoasts.isEmpty {
            text += "⭐ OPENING ROASTS (\(openingRoasts.count))\n"
            text += String(repeating: "-", count: 25) + "\n"
            
            for (i, joke) in openingRoasts.enumerated() {
                text += "\(i + 1). "
                if joke.isKiller { text += "🔥 " }
                text += "\(joke.content)\n"
                
                if includeStructure && joke.hasStructure {
                    if !joke.setup.isEmpty {
                        text += "   SETUP: \(joke.setup)\n"
                    }
                    if !joke.punchline.isEmpty {
                        text += "   PUNCHLINE: \(joke.punchline)\n"
                    }
                }
                
                if includeNotes && !joke.performanceNotes.isEmpty {
                    text += "   NOTES: \(joke.performanceNotes)\n"
                }
                
                if joke.isTested {
                    text += "   (Performed \(joke.performanceCount)x)\n"
                }
                
                // Show backups for this opener
                let backupsForOpener = backupRoasts.filter { $0.parentOpeningRoastID == joke.id }
                if !backupsForOpener.isEmpty {
                    text += "   BACKUPS:\n"
                    for backup in backupsForOpener {
                        text += "   ↳ \(backup.content)\n"
                        if includeNotes && !backup.performanceNotes.isEmpty {
                            text += "      NOTES: \(backup.performanceNotes)\n"
                        }
                    }
                }
                
                text += "\n"
                jokeIndex += 1
            }
        }
        
        // Unassigned roasts section
        if !unassignedRoasts.isEmpty {
            text += "\nOTHER ROASTS (\(unassignedRoasts.count))\n"
            text += String(repeating: "-", count: 25) + "\n"
            
            for joke in unassignedRoasts {
                text += "\(jokeIndex). "
                if joke.isKiller { text += "⭐️ " }
                text += "\(joke.content)\n"
                
                if includeStructure && joke.hasStructure {
                    if !joke.setup.isEmpty {
                        text += "   SETUP: \(joke.setup)\n"
                    }
                    if !joke.punchline.isEmpty {
                        text += "   PUNCHLINE: \(joke.punchline)\n"
                    }
                }
                
                if includeNotes && !joke.performanceNotes.isEmpty {
                    text += "   NOTES: \(joke.performanceNotes)\n"
                }
                
                if joke.isTested {
                    text += "   (Performed \(joke.performanceCount)x)\n"
                }
                
                text += "\n"
                jokeIndex += 1
            }
        }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "Roasts_\(target.name.replacingOccurrences(of: " ", with: "_")).txt"
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("⚠️ Failed to write text export: \(error)")
            return nil
        }
    }
    
    private func exportAsMarkdown() -> URL? {
        var md = "# Roasts for \(target.name)\n\n"
        
        if !target.notes.isEmpty {
            md += "> \(target.notes)\n\n"
        }
        
        if !target.traits.isEmpty {
            md += "## Traits\n"
            for trait in target.traits {
                md += "- \(trait)\n"
            }
            md += "\n"
        }
        
        let allJokes = target.sortedJokes
        let openingRoasts = allJokes.filter { $0.isOpeningRoast }.sorted { $0.displayOrder < $1.displayOrder }
        let backupRoasts = allJokes.filter { !$0.isOpeningRoast && $0.parentOpeningRoastID != nil }
        let unassignedRoasts = allJokes.filter { !$0.isOpeningRoast && $0.parentOpeningRoastID == nil }
        
        var jokeIndex = 1
        
        // Opening roasts section
        if !openingRoasts.isEmpty {
            md += "## ⭐ Opening Roasts (\(openingRoasts.count))\n\n"
            
            for (i, joke) in openingRoasts.enumerated() {
                md += "### \(i + 1). "
                if joke.isKiller { md += "🔥 " }
                md += "\(joke.title.isEmpty ? "Opening Roast" : joke.title)\n\n"
                md += "\(joke.content)\n\n"
                
                if includeStructure && joke.hasStructure {
                    if !joke.setup.isEmpty {
                        md += "**Setup:** \(joke.setup)\n\n"
                    }
                    if !joke.punchline.isEmpty {
                        md += "**Punchline:** \(joke.punchline)\n\n"
                    }
                }
                
                if includeNotes && !joke.performanceNotes.isEmpty {
                    md += "*Notes: \(joke.performanceNotes)*\n\n"
                }
                
                var meta: [String] = []
                if joke.isTested { meta.append("Performed \(joke.performanceCount)x") }
                if joke.relatabilityScore > 0 { meta.append("Relatability: \(joke.relatabilityScore)/5") }
                if !meta.isEmpty {
                    md += "`\(meta.joined(separator: " | "))`\n\n"
                }
                
                // Show backups for this opener
                let backupsForOpener = backupRoasts.filter { $0.parentOpeningRoastID == joke.id }
                if !backupsForOpener.isEmpty {
                    md += "#### Backups\n\n"
                    for backup in backupsForOpener {
                        md += "- ↳ \(backup.content)\n"
                        if includeNotes && !backup.performanceNotes.isEmpty {
                            md += "  - *Notes: \(backup.performanceNotes)*\n"
                        }
                    }
                    md += "\n"
                }
                
                md += "---\n\n"
                jokeIndex += 1
            }
        }
        
        // Unassigned roasts section
        if !unassignedRoasts.isEmpty {
            md += "## Other Roasts (\(unassignedRoasts.count))\n\n"
            
            for joke in unassignedRoasts {
                md += "### \(jokeIndex). "
                if joke.isKiller { md += "⭐️ " }
                md += "\(joke.title.isEmpty ? "Roast" : joke.title)\n\n"
                md += "\(joke.content)\n\n"
                
                if includeStructure && joke.hasStructure {
                    if !joke.setup.isEmpty {
                        md += "**Setup:** \(joke.setup)\n\n"
                    }
                    if !joke.punchline.isEmpty {
                        md += "**Punchline:** \(joke.punchline)\n\n"
                    }
                }
                
                if includeNotes && !joke.performanceNotes.isEmpty {
                    md += "*Notes: \(joke.performanceNotes)*\n\n"
                }
                
                var meta: [String] = []
                if joke.isTested { meta.append("Performed \(joke.performanceCount)x") }
                if joke.relatabilityScore > 0 { meta.append("Relatability: \(joke.relatabilityScore)/5") }
                if !meta.isEmpty {
                    md += "`\(meta.joined(separator: " | "))`\n\n"
                }
                
                md += "---\n\n"
                jokeIndex += 1
            }
        }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "Roasts_\(target.name.replacingOccurrences(of: " ", with: "_")).md"
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        do {
            try md.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("⚠️ Failed to write markdown export: \(error)")
            return nil
        }
    }
}

// MARK: - Edit Roast Joke Sheet

struct EditRoastJokeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var joke: RoastJoke
    @Query private var allRoastJokes: [RoastJoke]
    
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showAdvancedOptions = false
    @State private var showOpeningAssignment = false
    @FocusState private var isContentFocused: Bool
    
    private let accentColor: Color = .blue
    
    /// Safe content accessor
    private var safeContent: String {
        joke.isValid ? joke.content : ""
    }
    
    private var canSave: Bool {
        !safeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Get other opening roasts for this same target (for backup assignment)
    private var openingRoastsForTarget: [RoastJoke] {
        guard let targetName = joke.target?.name else { return [] }
        return allRoastJokes.filter { roast in
            guard !roast.isDeleted,
                  roast.isOpeningRoast,
                  roast.id != joke.id,
                  let name = roast.target?.name else { return false }
            return name == targetName
        }.sorted { $0.displayOrder < $1.displayOrder }
    }
    
    /// Get the opening roast this joke is a backup for
    private var parentOpeningRoast: RoastJoke? {
        guard let parentID = joke.parentOpeningRoastID else { return nil }
        return allRoastJokes.first { $0.id == parentID && !$0.isDeleted }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quick action toggles at top - always visible
                quickActions
                
                Divider()
                
                // Main content area
                ScrollView {
                    VStack(spacing: 16) {
                        // The roast content - main focus
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ROAST")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $joke.content)
                                .focused($isContentFocused)
                                .frame(minHeight: 120)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 16)
                        
                        // Optional structure fields - collapsible
                        DisclosureGroup(isExpanded: $showAdvancedOptions) {
                            VStack(spacing: 16) {
                                // Setup
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Setup / Premise")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    TextField("The lead-in...", text: $joke.setup, axis: .vertical)
                                        .padding(10)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(8)
                                }
                                
                                // Punchline
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Punchline")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    TextField("The payoff...", text: $joke.punchline, axis: .vertical)
                                        .padding(10)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(8)
                                }
                                
                                // Performance notes
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Notes")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    TextField("Timing, delivery, reactions...", text: $joke.performanceNotes, axis: .vertical)
                                        .padding(10)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(8)
                                }
                                
                        // Relatability score
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Audience Relatability")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 12) {
                                        ForEach(1...5, id: \.self) { score in
                                            Button {
                                                joke.relatabilityScore = joke.relatabilityScore == score ? 0 : score
                                            } label: {
                                                Image(systemName: score <= joke.relatabilityScore ? "person.fill" : "person")
                                                    .font(.title2)
                                                    .foregroundColor(score <= joke.relatabilityScore ? .blue : .gray.opacity(0.3))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.subheadline)
                                Text("Structure & Notes")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(accentColor)
                        }
                        .padding(.horizontal, 16)
                        
                        // Opening Roast / Backup Assignment Section
                        DisclosureGroup(isExpanded: $showOpeningAssignment) {
                            VStack(spacing: 16) {
                                // Opening Roast toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Mark as Opening Roast")
                                            .font(.subheadline.weight(.medium))
                                        let count = joke.target?.openingRoastCount ?? 3
                                        Text("One of \(count) main roast\(count == 1 ? "" : "s") for this target")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { joke.isOpeningRoast },
                                        set: { newValue in
                                            joke.isOpeningRoast = newValue
                                            if newValue {
                                                // Clear parent if becoming opening
                                                joke.parentOpeningRoastID = nil
                                            }
                                        }
                                    ))
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                                    .labelsHidden()
                                }
                                .padding(12)
                                .background(joke.isOpeningRoast ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                                .cornerRadius(10)
                                
                                // Backup assignment (only if not an opening roast)
                                if !joke.isOpeningRoast {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Assign as Backup For")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                        
                                        if openingRoastsForTarget.isEmpty {
                                            HStack {
                                                Image(systemName: "info.circle")
                                                    .foregroundColor(.secondary)
                                                Text("No opening roasts set for this target yet")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(12)
                                            .background(Color(.secondarySystemBackground))
                                            .cornerRadius(8)
                                        } else {
                                            // None option
                                            Button {
                                                joke.parentOpeningRoastID = nil
                                            } label: {
                                                HStack {
                                                    Text("None (Unassigned)")
                                                        .font(.subheadline)
                                                    Spacer()
                                                    if joke.parentOpeningRoastID == nil {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundColor(.blue)
                                                    }
                                                }
                                                .padding(12)
                                                .background(joke.parentOpeningRoastID == nil ? Color.gray.opacity(0.15) : Color(.secondarySystemBackground))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            // Opening roast options
                                            ForEach(Array(openingRoastsForTarget.enumerated()), id: \.element.id) { index, opening in
                                                Button {
                                                    joke.parentOpeningRoastID = opening.id
                                                } label: {
                                                    HStack(spacing: 10) {
                                                        Text("\(index + 1)")
                                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                                            .foregroundColor(.black)
                                                            .frame(width: 24, height: 24)
                                                            .background(Color.blue)
                                                            .clipShape(Circle())
                                                        
                                                        Text(opening.content.prefix(40) + (opening.content.count > 40 ? "..." : ""))
                                                            .font(.subheadline)
                                                            .foregroundColor(.primary)
                                                            .lineLimit(2)
                                                            .multilineTextAlignment(.leading)
                                                        
                                                        Spacer()
                                                        
                                                        if joke.parentOpeningRoastID == opening.id {
                                                            Image(systemName: "checkmark.circle.fill")
                                                                .foregroundColor(.blue)
                                                        }
                                                    }
                                                    .padding(12)
                                                    .background(joke.parentOpeningRoastID == opening.id ? Color.blue.opacity(0.15) : Color(.secondarySystemBackground))
                                                    .cornerRadius(8)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: joke.isOpeningRoast ? "star.circle.fill" : "arrow.turn.down.right")
                                    .font(.subheadline)
                                    .foregroundColor(joke.isOpeningRoast ? .blue : .blue)
                                Text(joke.isOpeningRoast ? "Opening Roast" : (joke.parentOpeningRoastID != nil ? "Backup Roast" : "Set Type"))
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(joke.isOpeningRoast ? .blue : (joke.parentOpeningRoastID != nil ? .blue : accentColor))
                        }
                        .padding(.horizontal, 16)
                        
                        // Stats if tested
                        if joke.isTested {
                            performanceStats
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                showAdvancedOptions = joke.hasStructure || !joke.performanceNotes.isEmpty
                showOpeningAssignment = joke.isOpeningRoast || joke.parentOpeningRoastID != nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveJoke()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(canSave ? accentColor : .secondary)
                    .disabled(!canSave)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Save") {
                            saveJoke()
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(canSave ? accentColor : .secondary)
                        .disabled(!canSave)
                    }
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    // MARK: - Quick Actions Row
    
    private var quickActions: some View {
        HStack(spacing: 0) {
            // Killer toggle
            QuickToggleButton(
                isOn: $joke.isKiller,
                icon: "star.fill",
                label: "Killer",
                activeColor: .blue
            )
            
            Divider()
                .frame(height: 30)
            
            // Tested toggle
            QuickToggleButton(
                isOn: $joke.isTested,
                icon: "checkmark.circle.fill",
                label: "Tested",
                activeColor: .blue
            )
            
            Divider()
                .frame(height: 30)
            
            // -1 Performance button
            Button {
                if joke.performanceCount > 0 {
                    joke.performanceCount -= 1
                    if joke.performanceCount == 0 {
                        joke.isTested = false
                        joke.lastPerformedDate = nil
                    }
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "minus.circle")
                        .font(.subheadline)
                    Text("-1")
                        .font(.caption2)
                }
                .foregroundColor(joke.performanceCount > 0 ? .blue : .secondary.opacity(0.3))
                .frame(width: 44)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(joke.performanceCount == 0)
            
            // +1 Performance button
            Button {
                joke.performanceCount += 1
                joke.lastPerformedDate = Date()
                joke.isTested = true
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                        Text("\(joke.performanceCount)")
                            .font(.subheadline.bold().monospacedDigit())
                    }
                    Text("Performed")
                        .font(.caption2)
                }
                .foregroundColor(joke.performanceCount > 0 ? .blue : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Performance Stats
    
    private var performanceStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                Text("Performance")
                    .font(.subheadline.bold())
                Spacer()
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(joke.performanceCount)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundColor(.blue)
                    Text("times")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let lastDate = joke.lastPerformedDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastDate, format: .dateTime.month(.abbreviated).day())
                            .font(.subheadline.bold())
                        Text("last performed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    private func saveJoke() {
        guard joke.isValid else {
            saveErrorMessage = "This roast was deleted and cannot be saved."
            showSaveError = true
            return
        }
        
        joke.dateModified = Date()
        do {
            try modelContext.save()
            dismiss()
        } catch {
            #if DEBUG
            print("⚠️ [EditRoastJokeView] Failed to save: \(error)")
            #endif
            saveErrorMessage = "Could not save changes: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}

// MARK: - Quick Toggle Button

struct QuickToggleButton: View {
    @Binding var isOn: Bool
    let icon: String
    let label: String
    let activeColor: Color
    
    var body: some View {
        Button {
            isOn.toggle()
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .foregroundColor(isOn ? activeColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Roast Target Sheet

struct EditRoastTargetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var target: RoastTarget

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private let accentColor: Color = .blue

    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            if let photoImage {
                                Image(uiImage: photoImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(accentColor, lineWidth: 3))
                            } else if let photoData = target.photoData,
                                      let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(accentColor, lineWidth: 3))
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(accentColor.opacity(0.12))
                                        .frame(width: 100, height: 100)
                                    VStack(spacing: 4) {
                                        Image(systemName: "person.crop.circle.badge.plus")
                                            .font(.system(size: 32))
                                            .foregroundColor(accentColor)
                                        Text("Add Photo")
                                            .font(.caption2)
                                            .foregroundColor(accentColor)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Name", text: $target.name)
                        .font(.headline)
                }

                Section("Notes (optional)") {
                    TextField("e.g. friend, coworker, celebrity...", text: $target.notes)
                }
                
                Section {
                    Picker("Main Roasts", selection: $target.openingRoastCount) {
                        ForEach(1...10, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Performance Settings")
                } footer: {
                    Text("Number of main opening roasts to prepare for this target during live performance.")
                }

                Section {
                    ForEach(Array(target.traits.enumerated()), id: \.offset) { index, _ in
                        if index < target.traits.count {
                            HStack {
                                TextField("e.g. works in finance, always late...", text: Binding(
                                    get: { index < target.traits.count ? target.traits[index] : "" },
                                    set: { newValue in
                                        if index < target.traits.count {
                                            target.traits[index] = newValue
                                        }
                                    }
                                ))
                                if target.traits.count > 1 {
                                    Button {
                                        if index < target.traits.count {
                                            target.traits.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Button {
                        target.traits.append("")
                    } label: {
                        Label("Add another", systemImage: "plus.circle")
                            .foregroundColor(accentColor)
                    }
                } header: {
                    Text("What do you know about them?")
                } footer: {
                    Text("Bullet points — habits, quirks, job, looks, anything roastable.")
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Photo data is already set via onChange handler with downscaling
                        target.dateModified = Date()
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            #if DEBUG
                            print(" [EditRoastTargetView] Failed to save: \(error)")
                            #endif
                            saveErrorMessage = "Could not save changes: \(error.localizedDescription)"
                            showSaveError = true
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(target.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .task(id: selectedPhoto) {
                await loadSelectedPhoto()
            }
            .onAppear {
                if let photoData = target.photoData {
                    photoImage = UIImage(data: photoData)
                }
            }
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        guard let data = try? await selectedPhoto.loadTransferable(type: Data.self),
              !Task.isCancelled,
              let original = UIImage(data: data) else {
            return
        }

        let scaled = RoastTargetPhotoHelper.downscale(original, maxLongEdge: 800)
        let scaledData = scaled.jpegData(compressionQuality: 0.8)

        await MainActor.run {
            guard target.photoData != scaledData else {
                self.selectedPhoto = nil
                return
            }
            target.photoData = scaledData
            photoImage = scaled
            self.selectedPhoto = nil
        }
    }
}
