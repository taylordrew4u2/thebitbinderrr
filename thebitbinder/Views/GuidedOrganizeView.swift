//
//  GuidedOrganizeView.swift
//  thebitbinder
//
//  Step-through guided organizer: presents one unorganized joke at a time
//  with AI-powered suggestions and manual override.
//

import SwiftUI
import SwiftData

struct GuidedOrganizeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    @Query(filter: #Predicate<JokeFolder> { !$0.isDeleted }) private var folders: [JokeFolder]
    @Query private var allJokes: [Joke]
    
    @State private var currentIndex = 0
    @State private var isLoadingSuggestions = false
    @State private var customFolderName = ""
    @State private var organizedCount = 0
    @State private var skippedCount = 0
    @State private var showingSummary = false
    
    private var unorganizedJokes: [Joke] {
        allJokes.filter { ($0.folders ?? []).isEmpty && !$0.isDeleted }
    }
    
    private var currentJoke: Joke? {
        guard currentIndex < unorganizedJokes.count else { return nil }
        return unorganizedJokes[currentIndex]
    }
    
    private var progress: Double {
        guard !unorganizedJokes.isEmpty else { return 1.0 }
        return Double(currentIndex) / Double(unorganizedJokes.count)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showingSummary {
                    summaryView
                } else if let joke = currentJoke {
                    jokeStepView(joke: joke)
                } else {
                    allDoneView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if !showingSummary && currentJoke != nil {
                        Text("\(currentIndex + 1) of \(unorganizedJokes.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Joke Step View
    
    @ViewBuilder
    private func jokeStepView(joke: Joke) -> some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: progress)
                .tint(.accentColor)
                .padding(.horizontal)
                .padding(.top, 8)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Joke content card
                    VStack(alignment: .leading, spacing: 12) {
                        Text(joke.title)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Text(joke.content)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // AI Suggestions
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: AutoOrganizeService.isAIAvailable ? "sparkles" : "lightbulb.fill")
                                .foregroundColor(.accentColor)
                            Text(AutoOrganizeService.isAIAvailable ? "AI Suggestions" : "Suggestions")
                                .font(.headline)
                            Spacer()
                            if isLoadingSuggestions {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .padding(.horizontal)
                        
                        if joke.categorizationResults.isEmpty && !isLoadingSuggestions {
                            Text("Analyzing...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .onAppear {
                                    loadSuggestions(for: joke)
                                }
                        } else {
                            ForEach(joke.categorizationResults, id: \.category) { match in
                                Button {
                                    acceptCategory(joke: joke, category: match.category)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(.accentColor)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(match.category)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.primary)
                                            Text(match.reasoning)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(match.confidencePercent)
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(confidenceColor(match.confidence))
                                            .cornerRadius(6)
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Existing folders
                    if !folders.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Existing Folders")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(folders) { folder in
                                    Button {
                                        acceptCategory(joke: joke, category: folder.name)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "folder")
                                                .font(.caption)
                                            Text(folder.name)
                                                .font(.caption.weight(.medium))
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 8)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Custom folder input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or Create New Folder")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        HStack {
                            TextField("New folder name...", text: $customFolderName)
                                .textFieldStyle(.roundedBorder)
                            
                            Button {
                                let name = customFolderName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                acceptCategory(joke: joke, category: name)
                                customFolderName = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }
                            .disabled(customFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.top, 12)
            }
            
            // Bottom action bar
            HStack(spacing: 16) {
                Button {
                    skipJoke()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("Skip")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                Button {
                    showingSummary = true
                } label: {
                    Text("Finish Early")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
    
    // MARK: - Summary
    
    private var summaryView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Guided Organize Complete!")
                .font(.title2.bold())
            
            VStack(spacing: 8) {
                HStack {
                    Text("Organized:")
                    Spacer()
                    Text("\(organizedCount) joke\(organizedCount == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Skipped:")
                    Spacer()
                    Text("\(skippedCount)")
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Remaining:")
                    Spacer()
                    Text("\(max(0, unorganizedJokes.count))")
                        .fontWeight(.semibold)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
            .padding(.horizontal, 32)
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - All Done
    
    private var allDoneView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "party.popper.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("All Jokes Organized!")
                .font(.title2.bold())
            
            Text("Every joke has been assigned to a folder.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if organizedCount > 0 {
                Text("You organized \(organizedCount) joke\(organizedCount == 1 ? "" : "s") this session.")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Actions
    
    private func loadSuggestions(for joke: Joke) {
        guard joke.categorizationResults.isEmpty else { return }
        isLoadingSuggestions = true
        
        Task { @MainActor in
            let existingFolderNames = folders.map { $0.name }
            let matches = await AutoOrganizeService.aiCategorize(
                content: joke.content,
                existingFolders: existingFolderNames
            )
            joke.categorizationResults = matches
            joke.saveCategorizationResults()
            isLoadingSuggestions = false
        }
    }
    
    private func acceptCategory(joke: Joke, category: String) {
        // Find or create folder
        var targetFolder = folders.first(where: { $0.name == category })
        if targetFolder == nil {
            let newFolder = JokeFolder(name: category)
            modelContext.insert(newFolder)
            targetFolder = newFolder
        }
        
        // Assign joke to folder
        if let folder = targetFolder, !(joke.folders ?? []).contains(where: { $0.id == folder.id }) {
            var current = joke.folders ?? []
            current.append(folder)
            joke.folders = current
        }
        
        // Set primary category
        joke.category = category
        joke.primaryCategory = category
        
        do {
            try modelContext.save()
            organizedCount += 1
            #if DEBUG
            print(" [GuidedOrganize] Assigned '\(joke.title.prefix(20))' → '\(category)'")
            #endif
        } catch {
            print(" [GuidedOrganize] Failed to save: \(error)")
        }
        
        advanceToNext()
    }
    
    private func skipJoke() {
        skippedCount += 1
        advanceToNext()
    }
    
    private func advanceToNext() {
        customFolderName = ""
        // Since the joke was just organized (removed from unorganizedJokes),
        // the currentIndex already points to the next unorganized joke.
        // Only increment if we skipped (joke is still in the list).
        if currentIndex < unorganizedJokes.count {
            // Check if the current joke is still unorganized (was skipped)
            // If so, advance the index
            if let joke = currentJoke, (joke.folders ?? []).isEmpty {
                currentIndex += 1
            }
        }
        
        // Check if we've gone through all jokes
        if currentIndex >= unorganizedJokes.count {
            showingSummary = true
        }
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...:
            return .blue
        case 0.6..<0.8:
            return .blue
        case 0.4..<0.6:
            return .blue
        default:
            return .gray
        }
    }
}
