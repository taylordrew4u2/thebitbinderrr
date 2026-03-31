//
//  AutoOrganizeView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/7/25.
//

import SwiftUI
import SwiftData

struct AutoOrganizeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    @Query private var jokes: [Joke]
    @Query private var folders: [JokeFolder]
    
    private let categorizationService = BitBuddyService.shared
    
    @State private var categories = AutoOrganizeService.getCategories()
    @State private var showOrganizationSummary = false
    @State private var organizationStats: (organized: Int, suggested: Int) = (0, 0)
    @State private var selectedJoke: Joke?
    @State private var showCategoryDetails = false
    @State private var isAnalyzing = false
    @State private var analysisProgress = 0
    @State private var analysisTotal = 0
    @State private var errorMessage: String?
    @State private var showError = false
    
    // Folder management state
    @State private var showFolderSetup = false
    @State private var customFolders: [String] = []
    @State private var newFolderName = ""
    @State private var isGeneratingFolders = false
    @State private var useCustomFoldersOnly = false
    
    // Reorganize All state
    @State private var showReorganizeConfirmation = false
    @State private var deleteOldFoldersOnReorganize = true
    
    // Track if we've populated categorization results
    @State private var hasPopulatedCategorizationResults = false
    
    var unorganizedJokes: [Joke] {
        jokes.filter { $0.folders.isEmpty && !$0.isDeleted }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Quick Auto-Organize Button
                        if !unorganizedJokes.isEmpty {
                            VStack(spacing: 12) {
                                // Setup Folders Button
                                Button(action: { showFolderSetup = true }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.badge.gearshape")
                                            .font(.system(size: 16, weight: .semibold))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Setup Folders First")
                                                .font(.headline)
                                            Text("Create folders or let us suggest them")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.purple.opacity(0.8), .purple.opacity(0.6)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(10)
                                
                                // Auto-Organize Button
                                Button(action: performAutoOrganize) {
                                    if isAnalyzing {
                                        HStack(spacing: 12) {
                                            ProgressView()
                                                .tint(.white)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Analyzing...")
                                                    .font(.headline)
                                                Text("\(analysisProgress)/\(analysisTotal) jokes analyzed")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                            Spacer()
                                        }
                                    } else {
                                        HStack(spacing: 12) {
                                            Image(systemName: "wand.and.stars")
                                                .font(.system(size: 16, weight: .semibold))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Smart Auto-Organize")
                                                    .font(.headline)
                                                Text(customFolders.isEmpty ? "Will create folders automatically" : "Using \(customFolders.count) custom folders")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                    }
                                }
                                .disabled(isAnalyzing)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue.opacity(0.8), .blue.opacity(0.6)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(10)
                                
                                // Reorganize All Button
                                Button(action: { showReorganizeConfirmation = true }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 16, weight: .semibold))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Reorganize All Jokes")
                                                .font(.headline)
                                            Text("Clear all folders & start fresh")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                }
                                .disabled(isAnalyzing)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.orange.opacity(0.8), .orange.opacity(0.6)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(10)
                            }
                            .padding()
                        }
                        
                        // Unorganized Jokes Section
                        if !unorganizedJokes.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Suggested Categories (\(unorganizedJokes.count))")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ForEach(unorganizedJokes) { joke in
                                    JokeOrganizationCard(
                                        joke: joke,
                                        onTap: {
                                            selectedJoke = joke
                                            showCategoryDetails = true
                                        },
                                        onAccept: { category in
                                            assignJokeToFolder(joke, category: category)
                                        }
                                    )
                                }
                            }
                            .padding()
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(AppTheme.Colors.success)
                                Text("All Jokes Organized!")
                                    .font(.headline)
                                Text("Your jokes have been sorted into categories with confidence scoring")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                // Reorganize All option when everything is already organized
                                Button(action: { showReorganizeConfirmation = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Reorganize All")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.orange.opacity(0.1))
                                    )
                                }
                                .disabled(isAnalyzing)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding()
                        }
                        
                        if !unorganizedJokes.isEmpty {
                            Divider()
                                .padding(.vertical)
                        }
                        
                        // Category Management Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("All Categories")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                ForEach(categories, id: \.self) { category in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(category)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            let jokeCount = jokes.filter { $0.folder?.name == category }.count
                                            if jokeCount > 0 {
                                                Text("\(jokeCount) jokes")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(AppTheme.Colors.primaryAction)
                                            .opacity(0.6)
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Smart Auto-Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showOrganizationSummary) {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(AppTheme.Colors.success)
                        
                        Text("Auto-Organization Complete!")
                            .font(.title2.bold())
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("Jokes Organized:")
                                Spacer()
                                Text("\(organizationStats.organized)")
                                    .fontWeight(.semibold)
                            }
                            
                            if organizationStats.suggested > 0 {
                                HStack {
                                    Text("Suggested Categories:")
                                    Spacer()
                                    Text("\(organizationStats.suggested)")
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .padding()
                        .background(AppTheme.Colors.surfaceElevated)
                        .cornerRadius(8)
                        
                        Text("Your jokes have been analyzed and categorized automatically.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                    
                    Button(action: { showOrganizationSummary = false; dismiss() }) {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.Colors.primaryAction)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .alert("Analysis Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred during analysis.")
            }
            .sheet(isPresented: $showCategoryDetails) {
                if let joke = selectedJoke {
                    CategorySuggestionDetail(
                        joke: joke,
                        onSelectCategory: { category in
                            assignJokeToFolder(joke, category: category)
                            showCategoryDetails = false
                        }
                    )
                }
            }
            .sheet(isPresented: $showFolderSetup) {
                FolderSetupView(
                    customFolders: $customFolders,
                    useCustomFoldersOnly: $useCustomFoldersOnly,
                    unorganizedJokes: unorganizedJokes,
                    existingFolders: folders.map { $0.name }
                )
            }
            .alert("Organization Complete", isPresented: $showOrganizationSummary) {
                Button("Done") { }
            } message: {
                Text("✅ Organized: \(organizationStats.organized) jokes\n📂 Folder assignments: \(organizationStats.suggested)")
            }
            .confirmationDialog(
                "Reorganize All Jokes",
                isPresented: $showReorganizeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reorganize & Keep Old Folders") {
                    deleteOldFoldersOnReorganize = false
                    performReorganizeAll()
                }
                Button("Reorganize & Delete Empty Folders", role: .destructive) {
                    deleteOldFoldersOnReorganize = true
                    performReorganizeAll()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove all jokes from their current folders and reorganize them into new categories.\n\n⚠️ No jokes will be deleted — only folder assignments will change.")
            }
            .onAppear {
                // Pre-populate categorization results for all unorganized jokes
                // so cards show suggestions immediately
                if !hasPopulatedCategorizationResults {
                    hasPopulatedCategorizationResults = true
                    for joke in unorganizedJokes {
                        if joke.categorizationResults.isEmpty {
                            let matches = AutoOrganizeService.categorize(content: joke.content)
                            joke.categorizationResults = matches
                            #if DEBUG
                            print("🎭 [AutoOrganize] Pre-populated \(matches.count) suggestions for: \(joke.title.prefix(30))")
                            #endif
                        }
                    }
                }
            }
        }
    }
    
    private func performAutoOrganize() {
        isAnalyzing = true
        // Capture a snapshot of unorganized jokes BEFORE we start modifying them
        let jokesToOrganize = unorganizedJokes
        analysisTotal = jokesToOrganize.count
        analysisProgress = 0
        errorMessage = nil
        
        guard !jokesToOrganize.isEmpty else {
            isAnalyzing = false
            return
        }
        
        Task {
            do {
                #if DEBUG
                print("🎭 [AutoOrganize] Starting analysis of \(jokesToOrganize.count) jokes...")
                #endif
                
                let availableFolders = customFolders.isEmpty ? nil : customFolders
                var organizedCount = 0
                var totalFolderAssignments = 0
                
                for joke in jokesToOrganize {
                    await MainActor.run {
                        analysisProgress += 1
                    }
                    
                    // Get ALL matching categories for this joke (not just the top one)
                    let allMatches: [CategoryMatch]
                    if let custom = availableFolders, useCustomFoldersOnly {
                        // Use custom folders - match joke against each custom folder
                        allMatches = await matchJokeToMultipleFolders(joke.content, folders: custom)
                    } else {
                        // Use AI analysis to get primary category, then also use local categorization for additional matches
                        let aiAnalysis = try await categorizationService.analyzeJoke(joke.content)
                        let localMatches = AutoOrganizeService.categorize(content: joke.content)
                        
                        // Combine: AI category as primary + local matches that pass threshold
                        var combined: [CategoryMatch] = []
                        
                        // Add AI category first
                        combined.append(CategoryMatch(
                            category: aiAnalysis.category,
                            confidence: 0.9,
                            reasoning: "AI-suggested primary category",
                            matchedKeywords: [],
                            styleTags: [],
                            emotionalTone: nil,
                            craftSignals: [],
                            structureScore: 0
                        ))
                        
                        // Add local matches that are different from AI category
                        for match in localMatches where match.confidence >= 0.35 && match.category != aiAnalysis.category {
                            combined.append(match)
                        }
                        
                        allMatches = combined
                    }
                    
                    // Update on main actor for SwiftData safety
                    await MainActor.run {
                        // Set primary category from top match
                        if let topMatch = allMatches.first {
                            joke.category = topMatch.category
                            joke.primaryCategory = topMatch.category
                        }
                        
                        // Store all categories
                        joke.allCategories = allMatches.map { $0.category }
                        
                        // Assign joke to MULTIPLE folders (one per matching category)
                        var assignedFolderNames: Set<String> = []
                        
                        for match in allMatches {
                            // Skip if we've already assigned to a folder with this name (prevent duplicates)
                            guard !assignedFolderNames.contains(match.category) else { continue }
                            
                            // Find or create the folder
                            var targetFolder = folders.first(where: { $0.name == match.category })
                            if targetFolder == nil {
                                let newFolder = JokeFolder(name: match.category)
                                modelContext.insert(newFolder)
                                targetFolder = newFolder
                                #if DEBUG
                                print("🎭 [AutoOrganize] Created new folder: \(match.category)")
                                #endif
                            }
                            
                            // Add joke to this folder (if not already in it)
                            if let folder = targetFolder, !joke.folders.contains(where: { $0.id == folder.id }) {
                                joke.folders.append(folder)
                                assignedFolderNames.insert(match.category)
                                totalFolderAssignments += 1
                                #if DEBUG
                                print("🎭 [AutoOrganize] Assigned joke '\(joke.title.prefix(20))' → folder '\(folder.name)'")
                                #endif
                            }
                        }
                        
                        if !assignedFolderNames.isEmpty {
                            organizedCount += 1
                        }
                    }
                }
                
                // Save all changes
                await MainActor.run {
                    do {
                        try modelContext.save()
                        #if DEBUG
                        print("✅ [AutoOrganize] Saved \(organizedCount) jokes to \(totalFolderAssignments) folder assignments")
                        #endif
                        organizationStats = (organizedCount, totalFolderAssignments)
                        showOrganizationSummary = true
                        isAnalyzing = false
                    } catch {
                        #if DEBUG
                        print("❌ [AutoOrganize] Save failed: \(error)")
                        #endif
                        errorMessage = "Failed to save: \(error.localizedDescription)"
                        showError = true
                        isAnalyzing = false
                    }
                }
            } catch {
                await MainActor.run {
                    #if DEBUG
                    print("❌ [AutoOrganize] Analysis failed: \(error)")
                    #endif
                    errorMessage = error.localizedDescription
                    showError = true
                    isAnalyzing = false
                }
            }
        }
    }
    
    /// Match a joke against multiple custom folders and return all matches above threshold
    private func matchJokeToMultipleFolders(_ jokeText: String, folders: [String]) async -> [CategoryMatch] {
        let normalizedJoke = jokeText.lowercased()
        let jokeTokens = Set(normalizedJoke.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        
        var matches: [CategoryMatch] = []
        
        for folder in folders {
            let folderLower = folder.lowercased()
            let folderTokens = Set(folderLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            
            // Calculate overlap score
            let overlap = folderTokens.intersection(jokeTokens).count
            let containsFolder = normalizedJoke.contains(folderLower)
            
            // Score: direct match is high confidence, token overlap is medium
            let confidence: Double
            if containsFolder {
                confidence = 0.9
            } else if overlap > 0 {
                confidence = min(0.3 + Double(overlap) * 0.15, 0.8)
            } else {
                confidence = 0.0
            }
            
            if confidence >= 0.3 {
                matches.append(CategoryMatch(
                    category: folder,
                    confidence: confidence,
                    reasoning: containsFolder ? "Direct mention in joke" : "Matched \(overlap) keyword(s)",
                    matchedKeywords: Array(folderTokens.intersection(jokeTokens)),
                    styleTags: [],
                    emotionalTone: nil,
                    craftSignals: [],
                    structureScore: 0
                ))
            }
        }
        
        // Sort by confidence
        return matches.sorted { $0.confidence > $1.confidence }
    }
    
    /// Analyze a joke and pick from user-provided folders using local heuristics.
    private func analyzeJokeWithFolders(_ jokeText: String, folders: [String]) async throws -> JokeAnalysis {
        let baseAnalysis = try await categorizationService.analyzeJoke(jokeText)
        let normalizedJoke = jokeText.lowercased()
        
        let scoredFolders: [(String, Int)] = folders.map { folder in
            let folderLower = folder.lowercased()
            let folderTokens = Set(folderLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let jokeTokens = Set(normalizedJoke.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let overlap = folderTokens.intersection(jokeTokens).count
            let categoryMatch = folderLower == baseAnalysis.category.lowercased() ? 5 : 0
            let tagMatch = baseAnalysis.tags.filter { folderLower.contains($0.lowercased()) }.count * 2
            return (folder, overlap + categoryMatch + tagMatch)
        }
        
        let bestFolder = scoredFolders.max(by: { $0.1 < $1.1 })?.0 ?? folders.first ?? baseAnalysis.category
        
        return JokeAnalysis(
            category: bestFolder,
            tags: baseAnalysis.tags,
            difficulty: baseAnalysis.difficulty,
            humorRating: baseAnalysis.humorRating
        )
    }
    
    
    private func assignJokeToFolder(_ joke: Joke, category: String) {
        #if DEBUG
        print("🎭 [AutoOrganize] Assigning joke '\(joke.title.prefix(20))' to folder '\(category)'")
        #endif
        
        // Find existing folder or create a new one
        var targetFolder = folders.first(where: { $0.name == category })
        
        if targetFolder == nil {
            let newFolder = JokeFolder(name: category)
            modelContext.insert(newFolder)
            targetFolder = newFolder
            #if DEBUG
            print("🎭 [AutoOrganize] Created new folder: \(category)")
            #endif
        }
        
        // Add to folders array (not replace) - prevents duplicates
        if let folder = targetFolder, !joke.folders.contains(where: { $0.id == folder.id }) {
            joke.folders.append(folder)
        }
        
        // Set primary category if not already set
        if joke.primaryCategory == nil {
            joke.category = category
            joke.primaryCategory = category
        }
        
        do {
            try modelContext.save()
            #if DEBUG
            print("✅ [AutoOrganize] Saved joke to folder '\(category)' (now in \(joke.folders.count) folders)")
            #endif
        } catch {
            print("❌ [AutoOrganizeView] Failed to save folder assignment: \(error)")
        }
    }
    
    // MARK: - Reorganize All
    
    /// Removes all folder assignments from all jokes, optionally deletes empty folders, then reorganizes everything
    private func performReorganizeAll() {
        isAnalyzing = true
        
        // Get all non-deleted jokes (not just unorganized)
        let allActiveJokes = jokes.filter { !$0.isDeleted }
        analysisTotal = allActiveJokes.count
        analysisProgress = 0
        errorMessage = nil
        
        guard !allActiveJokes.isEmpty else {
            isAnalyzing = false
            return
        }
        
        #if DEBUG
        print("🔄 [Reorganize] Starting reorganization of \(allActiveJokes.count) jokes...")
        print("🔄 [Reorganize] Delete empty folders after: \(deleteOldFoldersOnReorganize)")
        #endif
        
        Task {
            do {
                // STEP 1: Clear all folder assignments from all jokes
                await MainActor.run {
                    #if DEBUG
                    print("🔄 [Reorganize] Step 1: Clearing all folder assignments...")
                    #endif
                    
                    for joke in allActiveJokes {
                        joke.folders = []
                        joke.category = nil
                        joke.primaryCategory = nil
                        joke.allCategories = []
                        joke.categorizationResults = []
                    }
                    
                    // Save the cleared state
                    do {
                        try modelContext.save()
                        #if DEBUG
                        print("✅ [Reorganize] Cleared folder assignments from \(allActiveJokes.count) jokes")
                        #endif
                    } catch {
                        print("❌ [Reorganize] Failed to clear assignments: \(error)")
                    }
                }
                
                // STEP 2: Delete empty folders if requested
                if deleteOldFoldersOnReorganize {
                    await MainActor.run {
                        let emptyFolders = folders.filter { folder in
                            // A folder is empty if no jokes reference it
                            !allActiveJokes.contains(where: { $0.folders.contains(where: { $0.id == folder.id }) })
                        }
                        
                        #if DEBUG
                        print("🗑️ [Reorganize] Deleting \(emptyFolders.count) empty folders...")
                        #endif
                        
                        for folder in emptyFolders {
                            modelContext.delete(folder)
                        }
                        
                        do {
                            try modelContext.save()
                            #if DEBUG
                            print("✅ [Reorganize] Deleted empty folders")
                            #endif
                        } catch {
                            print("❌ [Reorganize] Failed to delete folders: \(error)")
                        }
                    }
                }
                
                // STEP 3: Reorganize all jokes (reuse existing logic)
                let availableFolders = customFolders.isEmpty ? nil : customFolders
                var organizedCount = 0
                var totalFolderAssignments = 0
                
                for joke in allActiveJokes {
                    await MainActor.run {
                        analysisProgress += 1
                    }
                    
                    // Get ALL matching categories for this joke
                    let allMatches: [CategoryMatch]
                    if let custom = availableFolders, useCustomFoldersOnly {
                        allMatches = await matchJokeToMultipleFolders(joke.content, folders: custom)
                    } else {
                        // Use AI + local heuristics
                        let aiAnalysis = try await categorizationService.analyzeJoke(joke.content)
                        let localMatches = AutoOrganizeService.categorize(content: joke.content)
                        
                        var combined: [CategoryMatch] = []
                        combined.append(CategoryMatch(
                            category: aiAnalysis.category,
                            confidence: 0.9,
                            reasoning: "AI-suggested primary category",
                            matchedKeywords: [],
                            styleTags: [],
                            emotionalTone: nil,
                            craftSignals: [],
                            structureScore: 0
                        ))
                        
                        for match in localMatches where match.confidence >= 0.35 && match.category != aiAnalysis.category {
                            combined.append(match)
                        }
                        
                        allMatches = combined
                    }
                    
                    // Assign to folders
                    await MainActor.run {
                        if let topMatch = allMatches.first {
                            joke.category = topMatch.category
                            joke.primaryCategory = topMatch.category
                        }
                        
                        joke.allCategories = allMatches.map { $0.category }
                        
                        var assignedFolderNames: Set<String> = []
                        
                        for match in allMatches {
                            guard !assignedFolderNames.contains(match.category) else { continue }
                            
                            var targetFolder = folders.first(where: { $0.name == match.category })
                            if targetFolder == nil {
                                let newFolder = JokeFolder(name: match.category)
                                modelContext.insert(newFolder)
                                targetFolder = newFolder
                            }
                            
                            if let folder = targetFolder, !joke.folders.contains(where: { $0.id == folder.id }) {
                                joke.folders.append(folder)
                                assignedFolderNames.insert(match.category)
                                totalFolderAssignments += 1
                            }
                        }
                        
                        if !assignedFolderNames.isEmpty {
                            organizedCount += 1
                        }
                    }
                }
                
                // Save all changes
                await MainActor.run {
                    do {
                        try modelContext.save()
                        #if DEBUG
                        print("✅ [Reorganize] Complete! Organized \(organizedCount) jokes into \(totalFolderAssignments) folder assignments")
                        #endif
                        organizationStats = (organizedCount, totalFolderAssignments)
                        showOrganizationSummary = true
                        isAnalyzing = false
                        hasPopulatedCategorizationResults = false // Reset so cards refresh
                    } catch {
                        print("❌ [Reorganize] Failed to save: \(error)")
                        errorMessage = "Failed to save: \(error.localizedDescription)"
                        showError = true
                        isAnalyzing = false
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ [Reorganize] Failed: \(error)")
                    errorMessage = error.localizedDescription
                    showError = true
                    isAnalyzing = false
                }
            }
        }
    }
}

// MARK: - Joke Organization Card

struct JokeOrganizationCard: View {
    let joke: Joke
    let onTap: () -> Void
    let onAccept: (String) -> Void
    
    @State private var hasPopulatedResults = false
    
    var topSuggestion: CategoryMatch? {
        joke.categorizationResults.first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(joke.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
            
            Text(joke.content)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            if let suggestion = topSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.category)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.Colors.primaryAction)
                            
                            Text(suggestion.reasoning)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(suggestion.confidencePercent)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(confidenceColor(suggestion.confidence))
                                .cornerRadius(6)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Button(action: { onAccept(suggestion.category) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                Text("Accept")
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.Colors.success)
                            .cornerRadius(6)
                        }
                        
                        Button(action: onTap) {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                Text("Choose")
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.primaryAction)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.Colors.primaryAction.opacity(0.1))
                            .cornerRadius(6)
                        }
                        
                        Spacer()
                    }
                }
                .padding(12)
                .background(AppTheme.Colors.primaryAction.opacity(0.05))
                .cornerRadius(8)
            } else {
                // No suggestion available - try to generate one or show manual option
                VStack(alignment: .leading, spacing: 8) {
                    if !hasPopulatedResults {
                        ProgressView()
                            .onAppear {
                                // Try to populate results if empty
                                if joke.categorizationResults.isEmpty {
                                    let matches = AutoOrganizeService.categorize(content: joke.content)
                                    joke.categorizationResults = matches
                                }
                                hasPopulatedResults = true
                            }
                    } else {
                        Text("No automatic suggestion")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: onTap) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                Text("Choose Category")
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.primaryAction)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.Colors.primaryAction.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(12)
                .background(AppTheme.Colors.warning.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...:
            return .green
        case 0.6..<0.8:
            return .blue
        case 0.4..<0.6:
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - Category Suggestion Detail

struct CategorySuggestionDetail: View {
    @Environment(\.dismiss) var dismiss
    @State private var customFolderName: String = ""
    
    let joke: Joke
    let onSelectCategory: (String) -> Void
    
    var body: some View {
        NavigationStack {
            VStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(joke.title)
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text(joke.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(12)
                .padding()
                
                Text("Smart Suggestions")
                    .font(.headline)
                    .padding(.horizontal)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(joke.categorizationResults, id: \.category) { match in
                            Button(action: { onSelectCategory(match.category) }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(match.category)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            
                                            Text(match.reasoning)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing) {
                                            Text(match.confidencePercent)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(confidenceColor(match.confidence))
                                                .cornerRadius(6)
                                        }
                                    }
                                    
                                    if !match.matchedKeywords.isEmpty {
                                        Wrap(match.matchedKeywords) { keyword in
                                            Text(keyword)
                                                .font(.caption)
                                                .foregroundColor(AppTheme.Colors.primaryAction)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(AppTheme.Colors.primaryAction.opacity(0.1))
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                        // Custom Folder Input
                        Divider().padding(.vertical)
                        Text("Create New Folder")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        HStack {
                            TextField("New folder name...", text: $customFolderName)
                                .textFieldStyle(.roundedBorder)
                            Button(action: {
                                if !customFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                                    onSelectCategory(customFolderName.trimmingCharacters(in: .whitespaces))
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                            }
                        }
                        .padding(.horizontal)
                        
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Choose Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if joke.categorizationResults.isEmpty {
                    let matches = AutoOrganizeService.categorize(content: joke.content)
                    joke.categorizationResults = matches
                }
            }
        }
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...:
            return .green
        case 0.6..<0.8:
            return .blue
        case 0.4..<0.6:
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - Wrap Helper for Keyword Display

struct Wrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content
    
    init(_ items: [String], @ViewBuilder content: @escaping (String) -> Content) {
        self.items = items
        self.content = content
    }
    
    var body: some View {
        var width: CGFloat = .zero
        var height: CGFloat = .zero
        
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > UIScreen.main.bounds.width - 32 {
                            width = 0
                            height -= dimension.height
                        }
                        let result = width
                        width -= dimension.width
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        return result
                    }
            }
        }
    }
}

// MARK: - Folder Setup View

struct FolderSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var customFolders: [String]
    @Binding var useCustomFoldersOnly: Bool
    
    let unorganizedJokes: [Joke]
    let existingFolders: [String]
    
    @State private var newFolderName = ""
    @State private var isGeneratingFolders = false
    @State private var suggestedFolders: [String] = []
    
    private let bitBuddy = BitBuddyService.shared
    
    var body: some View {
        NavigationStack {
            List {
                // AI Generate Section
                Section {
                    Button(action: generateAIFolders) {
                        HStack(spacing: 12) {
                            if isGeneratingFolders {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkles")
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Generate Smart Folders")
                                    .fontWeight(.semibold)
                                Text("Analyze your jokes and suggest folders")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .disabled(isGeneratingFolders)
                    
                    if !suggestedFolders.isEmpty {
                        ForEach(suggestedFolders, id: \.self) { folder in
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                                Text(folder)
                                Spacer()
                                if customFolders.contains(folder) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.Colors.success)
                                } else {
                                    Button("Add") {
                                        if !customFolders.contains(folder) {
                                            customFolders.append(folder)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        Button("Add All Suggestions") {
                            for folder in suggestedFolders {
                                if !customFolders.contains(folder) {
                                    customFolders.append(folder)
                                }
                            }
                        }
                        .foregroundColor(AppTheme.Colors.primaryAction)
                    }
                } header: {
                    Text("Smart Suggestions")
                } footer: {
                    Text("BitBuddy will analyze your \(unorganizedJokes.count) jokes and suggest folder categories.")
                }
                
                // Manual Create Section
                Section {
                    HStack {
                        TextField("New folder name...", text: $newFolderName)
                        Button(action: addCustomFolder) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(AppTheme.Colors.primaryAction)
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Create Your Own")
                }
                
                // Custom Folders List
                if !customFolders.isEmpty {
                    Section {
                        ForEach(customFolders, id: \.self) { folder in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                                Text(folder)
                                Spacer()
                            }
                        }
                        .onDelete(perform: deleteFolder)
                    } header: {
                        Text("Your Folders (\(customFolders.count))")
                    }
                }
                
                // Existing Folders
                if !existingFolders.isEmpty {
                    Section {
                        ForEach(existingFolders, id: \.self) { folder in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.gray)
                                Text(folder)
                                Spacer()
                                if customFolders.contains(folder) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.Colors.success)
                                } else {
                                    Button("Use") {
                                        if !customFolders.contains(folder) {
                                            customFolders.append(folder)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    } header: {
                        Text("Existing Folders")
                    } footer: {
                        Text("Add existing folders to use them for organization.")
                    }
                }
                
                // Options
                Section {
                    Toggle("Only use my folders", isOn: $useCustomFoldersOnly)
                } header: {
                    Text("Options")
                } footer: {
                    Text(useCustomFoldersOnly
                         ? "BitBuddy will only categorize into your selected folders."
                         : "BitBuddy may create new folders if jokes don't fit existing ones.")
                }
            }
            .navigationTitle("Setup Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func addCustomFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !customFolders.contains(name) else { return }
        customFolders.append(name)
        newFolderName = ""
    }
    
    private func deleteFolder(at offsets: IndexSet) {
        customFolders.remove(atOffsets: offsets)
    }
    
    private func generateAIFolders() {
        isGeneratingFolders = true
        
        Task {
            do {
                let sampleJokes = Array(unorganizedJokes.prefix(20))
                var buckets: [String: Int] = [:]
                for joke in sampleJokes {
                    let analysis = try await bitBuddy.analyzeJoke(joke.content)
                    buckets[analysis.category, default: 0] += 2
                    for tag in analysis.tags {
                        buckets[tag, default: 0] += 1
                    }
                }
                
                let suggestions = buckets
                    .sorted { lhs, rhs in
                        if lhs.value == rhs.value { return lhs.key < rhs.key }
                        return lhs.value > rhs.value
                    }
                    .map(\.key)
                    .filter { !$0.isEmpty }
                
                await MainActor.run {
                    suggestedFolders = Array(suggestions.prefix(6))
                    isGeneratingFolders = false
                }
            } catch {
                await MainActor.run {
                    isGeneratingFolders = false
                }
            }
        }
    }
}

