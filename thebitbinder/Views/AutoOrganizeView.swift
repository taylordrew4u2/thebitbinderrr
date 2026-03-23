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
    
    // Folder management state
    
    var unorganizedJokes: [Joke] {
        jokes.filter { $0.folder == nil }
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
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(AppTheme.Colors.success)
                                Text("All Jokes Organized!")
                                    .font(.headline)
                                Text("Your jokes have been sorted into categories with confidence scoring")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
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
                Text("✅ Organized: \(organizationStats.organized) jokes\n⚠️ Suggested: \(organizationStats.suggested) jokes")
            }
        }
    }
    
    private func performAutoOrganize() {
        isAnalyzing = true
        analysisTotal = unorganizedJokes.count
        analysisProgress = 0
        errorMessage = nil
        
        Task {
            do {
                #if DEBUG
                print("🎭 Starting analysis of \(unorganizedJokes.count) jokes...")
                #endif
                
                let availableFolders = customFolders.isEmpty ? nil : customFolders
                
                for joke in unorganizedJokes {
                    analysisProgress += 1
                    
                    let analysis: JokeAnalysis
                    if let custom = availableFolders, useCustomFoldersOnly {
                        analysis = try await analyzeJokeWithFolders(joke.content, folders: custom)
                    } else {
                        analysis = try await categorizationService.analyzeJoke(joke.content)
                    }
                    
                    joke.category = analysis.category
                    joke.tags = analysis.tags
                    joke.difficulty = analysis.difficulty
                    joke.humorRating = analysis.humorRating
                    
                    var targetFolder = folders.first(where: { $0.name == analysis.category })
                    if targetFolder == nil {
                        targetFolder = JokeFolder(name: analysis.category)
                        modelContext.insert(targetFolder!)
                    }
                    
                    joke.folder = targetFolder
                    #if DEBUG
                    print("🎭 Analyzed \(analysisProgress)/\(analysisTotal): \(analysis.category)")
                    #endif
                }
                
                try modelContext.save()
                
                await MainActor.run {
                    organizationStats = (unorganizedJokes.count, 0)
                    showOrganizationSummary = true
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isAnalyzing = false
                }
            }
        }
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
        var targetFolder = folders.first(where: { $0.name == category })
        
        if targetFolder == nil {
            targetFolder = JokeFolder(name: category)
            modelContext.insert(targetFolder!)
        }
        
        joke.folder = targetFolder
        try? modelContext.save()
    }
}

// MARK: - Joke Organization Card

struct JokeOrganizationCard: View {
    let joke: Joke
    let onTap: () -> Void
    let onAccept: (String) -> Void
    
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
                // No suggestion available
                VStack(alignment: .leading, spacing: 8) {
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
