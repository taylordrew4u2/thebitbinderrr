//
//  LivePerformanceView.swift
//  thebitbinder
//
//  Ultra-clean live performance view.
//  TAP LEFT = Previous | TAP RIGHT = Next | TAP CENTER = Controls
//  Built for stage use - big text, simple navigation, won't crash.
//

import SwiftUI
import SwiftData

struct LivePerformanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var jokes: [Joke]
    @Query private var roastJokes: [RoastJoke]
    @Query private var roastTargets: [RoastTarget]
    
    let setList: SetList
    
    @State private var currentIndex = 0
    @State private var showControls = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isTimerRunning = false
    @State private var showExitConfirmation = false
    @State private var fontSize: CGFloat = 28
    @State private var screenBrightness: CGFloat = 1.0
    @State private var cachedItems: [PerformanceItem] = []
    @State private var hasLoadedItems = false
    @State private var showHint = true
    @State private var showJokeList = false
    @State private var showBackupJokes = false
    @State private var showTargets = false
    
    // MARK: - Safe Model Access
    
    private var isSetListValid: Bool {
        guard setList.modelContext != nil else { return false }
        return !setList.id.uuidString.isEmpty
    }
    
    private var safeSetName: String {
        guard isSetListValid else { return "Set" }
        return setList.name.isEmpty ? "Set" : setList.name
    }
    
    private var safeItemCount: Int { cachedItems.count }
    
    private var safeCurrentIndex: Int {
        guard !cachedItems.isEmpty else { return 0 }
        return min(max(0, currentIndex), cachedItems.count - 1)
    }
    
    private var currentItem: PerformanceItem? {
        guard !cachedItems.isEmpty else { return nil }
        let idx = safeCurrentIndex
        guard idx >= 0 && idx < cachedItems.count else { return nil }
        return cachedItems[idx]
    }
    
    private var canGoPrevious: Bool { safeCurrentIndex > 0 && !cachedItems.isEmpty }
    private var canGoNext: Bool { !cachedItems.isEmpty && safeCurrentIndex < cachedItems.count - 1 }
    
    // Build items safely
    private func buildItems() -> [PerformanceItem] {
        var items: [PerformanceItem] = []
        guard isSetListValid else { return items }
        
        // Regular jokes
        for jokeID in setList.jokeIDs {
            guard let joke = jokes.first(where: { 
                $0.modelContext != nil && $0.id == jokeID && !$0.isDeleted 
            }) else { continue }
            
            items.append(PerformanceItem(
                id: joke.id,
                content: joke.content.isEmpty ? "(Empty)" : joke.content,
                setup: "", punchline: "", notes: "",
                isRoast: false, targetName: nil
            ))
        }
        
        // Roast jokes
        for roastID in setList.roastJokeIDs {
            guard let roast = roastJokes.first(where: { 
                $0.modelContext != nil && $0.id == roastID && !$0.isDeleted
            }) else { continue }
            
            var targetName: String? = nil
            if let target = roast.target, target.modelContext != nil, !target.name.isEmpty {
                targetName = target.name
            }
            
            items.append(PerformanceItem(
                id: roast.id,
                content: roast.content.isEmpty ? "(Empty)" : roast.content,
                setup: roast.setup, punchline: roast.punchline,
                notes: roast.performanceNotes,
                isRoast: true, targetName: targetName
            ))
        }
        
        return items
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Pure black background
                Color.black.ignoresSafeArea()
                
                // MAIN CONTENT
                VStack(spacing: 0) {
                    // Minimal top bar - always visible but subtle
                    minimalTopBar
                    
                    // THE JOKE - takes up most of screen
                    ZStack {
                        jokeContent
                        
                        // Invisible tap zones for navigation
                        HStack(spacing: 0) {
                            // TAP LEFT = Previous
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: geo.size.width * 0.25)
                                .onTapGesture {
                                    if canGoPrevious {
                                        goToPrevious()
                                    }
                                }
                            
                            // TAP CENTER = Toggle controls
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: geo.size.width * 0.5)
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showControls.toggle()
                                        showHint = false
                                    }
                                }
                            
                            // TAP RIGHT = Next
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: geo.size.width * 0.25)
                                .onTapGesture {
                                    if canGoNext {
                                        goToNext()
                                    }
                                }
                        }
                    }
                    
                    // Progress bar at bottom - always visible
                    progressBar
                }
                
                // Controls overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
                
                // First-time hint
                if showHint && !cachedItems.isEmpty {
                    hintOverlay
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { showHint = false }
                            }
                        }
                }
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            loadItemsSafely()
            UIApplication.shared.isIdleTimerDisabled = true
            screenBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            startTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            UIScreen.main.brightness = screenBrightness
            stopTimer()
        }
        .gesture(swipeGesture)
        .alert("Exit Performance?", isPresented: $showExitConfirmation) {
            Button("Stay", role: .cancel) { }
            Button("Exit", role: .destructive) {
                stopTimer()
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showJokeList) {
            jokeListOverlay
        }
        .fullScreenCover(isPresented: $showBackupJokes) {
            backupJokesOverlay
        }
        .fullScreenCover(isPresented: $showTargets) {
            targetsOverlay
        }
    }
    
    // MARK: - Minimal Top Bar
    
    private var minimalTopBar: some View {
        HStack {
            // Exit button
            Button {
                showExitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            // Progress + Timer
            VStack(spacing: 2) {
                Text("\(safeCurrentIndex + 1)/\(max(1, safeItemCount))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(timeString(from: elapsedTime))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Placeholder for symmetry
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
    
    // MARK: - Joke Content
    
    private var jokeContent: some View {
        VStack(spacing: 0) {
            if let item = currentItem {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Target name for roasts
                        if let targetName = item.targetName {
                            HStack(spacing: 8) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 20))
                                Text(targetName.uppercased())
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.blue)
                            .padding(.bottom, 8)
                        }
                        
                        // THE JOKE - big and clear
                        if item.hasStructure {
                            // Show structure
                            VStack(alignment: .leading, spacing: 24) {
                                if !item.setup.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("SETUP")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.blue)
                                        Text(item.setup)
                                            .font(.system(size: fontSize, weight: .regular))
                                            .foregroundColor(.white.opacity(0.95))
                                            .lineSpacing(6)
                                    }
                                }
                                
                                if !item.punchline.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("PUNCHLINE")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.blue)
                                        Text(item.punchline)
                                            .font(.system(size: fontSize + 4, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineSpacing(6)
                                    }
                                }
                            }
                        } else {
                            // Just the content - nice and big
                            Text(item.content)
                                .font(.system(size: fontSize, weight: .regular))
                                .foregroundColor(.white)
                                .lineSpacing(8)
                        }
                        
                        // Notes at bottom if any
                        if !item.notes.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                                Text(item.notes)
                                    .font(.system(size: max(14, fontSize - 8)))
                                    .foregroundColor(.blue.opacity(0.9))
                                    .italic()
                            }
                            .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            } else {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 70))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Empty Set")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)
                
                // Progress
                if safeItemCount > 0 {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geo.size.width * CGFloat(safeCurrentIndex + 1) / CGFloat(safeItemCount), height: 4)
                        .animation(.easeOut(duration: 0.2), value: currentIndex)
                }
            }
        }
        .frame(height: 4)
        .padding(.bottom, 20)
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 20) {
                // Quick access buttons - row 1: TARGETS is most important
                HStack(spacing: 16) {
                    // ROAST TARGETS - most important for roast shows
                    Button {
                        withAnimation { 
                            showControls = false
                            showTargets = true 
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 32))
                            Text("TARGETS")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 100, height: 75)
                        .background(.blue)
                        .cornerRadius(12)
                    }
                }
                
                // Quick access buttons - row 2
                HStack(spacing: 16) {
                    // See all jokes in set
                    Button {
                        withAnimation { 
                            showControls = false
                            showJokeList = true 
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 24))
                            Text("ALL JOKES")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 60)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(10)
                    }
                    
                    // Backup jokes
                    Button {
                        withAnimation { 
                            showControls = false
                            showBackupJokes = true 
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 24))
                            Text("BACKUPS")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 60)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(10)
                    }
                }
                
                // Font size
                HStack(spacing: 24) {
                    Text("Text Size")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    HStack(spacing: 16) {
                        Button {
                            fontSize = max(20, fontSize - 4)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                        
                        Text("\(Int(fontSize))")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 40)
                        
                        Button {
                            fontSize = min(48, fontSize + 4)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // Navigation buttons
                HStack(spacing: 40) {
                    Button {
                        goToPrevious()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 50))
                            Text("PREV")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(canGoPrevious ? .white : .white.opacity(0.3))
                    }
                    .disabled(!canGoPrevious)
                    
                    Button {
                        goToNext()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 50))
                            Text("NEXT")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(canGoNext ? .white : .white.opacity(0.3))
                    }
                    .disabled(!canGoNext)
                }
                
                // Tap to dismiss
                Text("Tap center to hide")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.vertical, 30)
            .padding(.horizontal, 40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.bottom, 50)
        }
        .background(Color.black.opacity(0.5))
        .onTapGesture {
            withAnimation { showControls = false }
        }
    }
    
    // MARK: - All Jokes List (Jump To)
    
    private var jokeListOverlay: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("SET LIST")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button {
                        withAnimation { showJokeList = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding()
                .background(Color.black)
                
                // List of jokes - tap to jump
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(cachedItems.enumerated()), id: \.element.id) { index, item in
                                JokeListRow(
                                    index: index,
                                    item: item,
                                    isCurrentIndex: index == safeCurrentIndex,
                                    fontSize: fontSize,
                                    onTap: {
                                        currentIndex = index
                                        withAnimation { showJokeList = false }
                                    }
                                )
                                .id(index)
                            }
                        }
                    }
                    .onAppear {
                        // Scroll to current joke
                        proxy.scrollTo(safeCurrentIndex, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Backup Jokes Drawer
    
    private var backupJokes: [Joke] {
        // All jokes NOT in this set list
        jokes.filter { joke in
            guard joke.modelContext != nil, !joke.isDeleted else { return false }
            return !setList.jokeIDs.contains(joke.id)
        }
    }
    
    private var backupRoasts: [RoastJoke] {
        // All roast jokes NOT in this set list
        roastJokes.filter { roast in
            guard roast.modelContext != nil, !roast.isDeleted else { return false }
            return !setList.roastJokeIDs.contains(roast.id)
        }
    }
    
    private var backupJokesOverlay: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BACKUP JOKES")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Tap any joke to view it")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation { showBackupJokes = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding()
                .background(Color.black)
                
                // Backup jokes list
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Regular jokes section
                        if !backupJokes.isEmpty {
                            HStack {
                                Text("Regular Jokes (\(backupJokes.count))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                            
                            ForEach(backupJokes) { joke in
                                BackupJokeRow(content: joke.content, isRoast: false, targetName: nil, fontSize: fontSize)
                            }
                        }
                        
                        // Roast jokes section
                        if !backupRoasts.isEmpty {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                Text("Roast Jokes (\(backupRoasts.count))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.blue.opacity(0.8))
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                            
                            ForEach(backupRoasts) { roast in
                                BackupJokeRow(
                                    content: roast.content,
                                    isRoast: true,
                                    targetName: roast.target?.name,
                                    fontSize: fontSize,
                                    setup: roast.setup,
                                    punchline: roast.punchline,
                                    notes: roast.performanceNotes
                                )
                            }
                        }
                        
                        // Empty state
                        if backupJokes.isEmpty && backupRoasts.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "tray")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.2))
                                Text("No backup jokes available")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.4))
                                Text("All your jokes are in this set!")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - Targets Overlay (Quick Access to All Roast Targets)
    
    /// Get unique targets from roasts in this set
    private var targetsInSet: [(name: String, roasts: [PerformanceItem])] {
        var targetMap: [String: [PerformanceItem]] = [:]
        
        for item in cachedItems where item.isRoast {
            let targetName = item.targetName ?? "Unknown"
            if targetMap[targetName] == nil {
                targetMap[targetName] = []
            }
            targetMap[targetName]?.append(item)
        }
        
        // Sort by target name
        return targetMap.sorted { $0.key < $1.key }.map { (name: $0.key, roasts: $0.value) }
    }
    
    /// Get ALL roasts grouped by target (including backups)
    private var allTargetsWithRoasts: [(name: String, inSet: [PerformanceItem], backups: [RoastJoke], allRoasts: [RoastJoke], openingCount: Int)] {
        var result: [(name: String, inSet: [PerformanceItem], backups: [RoastJoke], allRoasts: [RoastJoke], openingCount: Int)] = []
        
        // Get all roast jokes for lookup
        let allRoastJokes = roastJokes.filter { $0.modelContext != nil && !$0.isDeleted }
        
        // Start with targets in set
        for targetData in targetsInSet {
            // Find ALL roasts for this target (for opening/backup structure)
            let allRoastsForTarget = allRoastJokes.filter { roast in
                guard let targetName = roast.target?.name else { return false }
                return targetName == targetData.name
            }
            
            // Find backup roasts for this target (not in set)
            let backupsForTarget = backupRoasts.filter { roast in
                guard let targetName = roast.target?.name else { return false }
                return targetName == targetData.name
            }
            
            // Get opening roast count from target
            let openingCount = roastTargets.first { $0.name == targetData.name && !$0.isDeleted }?.openingRoastCount ?? 3
            
            result.append((name: targetData.name, inSet: targetData.roasts, backups: backupsForTarget, allRoasts: allRoastsForTarget, openingCount: openingCount))
        }
        
        // Add targets that only have backup roasts (not in set)
        let setTargetNames = Set(targetsInSet.map { $0.name })
        var additionalTargets: [String: (backups: [RoastJoke], allRoasts: [RoastJoke], openingCount: Int)] = [:]
        
        for roast in backupRoasts {
            guard let targetName = roast.target?.name, !setTargetNames.contains(targetName) else { continue }
            if additionalTargets[targetName] == nil {
                // Get all roasts for this target
                let allRoastsForTarget = allRoastJokes.filter { r in
                    guard let name = r.target?.name else { return false }
                    return name == targetName
                }
                let openingCount = roastTargets.first { $0.name == targetName && !$0.isDeleted }?.openingRoastCount ?? 3
                additionalTargets[targetName] = (backups: [], allRoasts: allRoastsForTarget, openingCount: openingCount)
            }
            additionalTargets[targetName]?.backups.append(roast)
        }
        
        for (name, data) in additionalTargets.sorted(by: { $0.key < $1.key }) {
            result.append((name: name, inSet: [], backups: data.backups, allRoasts: data.allRoasts, openingCount: data.openingCount))
        }
        
        return result
    }
    
    private var targetsOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ROAST TARGETS")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.blue)
                            Text("\(allTargetsWithRoasts.count) target\(allTargetsWithRoasts.count == 1 ? "" : "s")")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation { showTargets = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding()
                .background(Color.black)
                
                if allTargetsWithRoasts.isEmpty {
                    // No roasts
                    VStack(spacing: 20) {
                        Image(systemName: "flame.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.2))
                        Text("No Roast Targets")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                        Text("Add roast jokes to your set")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // List of targets
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(allTargetsWithRoasts, id: \.name) { targetData in
                                TargetSection(
                                    targetName: targetData.name,
                                    inSetRoasts: targetData.inSet,
                                    backupRoasts: targetData.backups,
                                    allRoastsForTarget: targetData.allRoasts,
                                    openingRoastCount: targetData.openingCount,
                                    fontSize: fontSize,
                                    onJumpToRoast: { item in
                                        // Find index in cachedItems
                                        if let index = cachedItems.firstIndex(where: { $0.id == item.id }) {
                                            currentIndex = index
                                            withAnimation { showTargets = false }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
    }
    
    // MARK: - Hint Overlay
    
    private var hintOverlay: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 0) {
                // Left hint
                VStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                    Text("PREV")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                
                // Center hint
                VStack {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 24))
                    Text("OPTIONS")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                
                // Right hint
                VStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .bold))
                    Text("NEXT")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 60)
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Gestures
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 60)
            .onEnded { value in
                let h = value.translation.width
                let v = value.translation.height
                if abs(h) > abs(v) {
                    if h < -60 { goToNext() }
                    else if h > 60 { goToPrevious() }
                }
            }
    }
    
    // MARK: - Actions
    
    private func loadItemsSafely() {
        guard !hasLoadedItems else { return }
        cachedItems = buildItems()
        hasLoadedItems = true
        if currentIndex >= cachedItems.count {
            currentIndex = max(0, cachedItems.count - 1)
        }
    }
    
    private func goToNext() {
        guard canGoNext else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            currentIndex = min(currentIndex + 1, cachedItems.count - 1)
        }
    }
    
    private func goToPrevious() {
        guard canGoPrevious else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            currentIndex = max(currentIndex - 1, 0)
        }
    }
    
    private func startTimer() {
        isTimerRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async { elapsedTime += 1 }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
    }
    
    private func timeString(from duration: TimeInterval) -> String {
        let s = Int(max(0, duration))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Performance Item Model

struct PerformanceItem: Identifiable {
    let id: UUID
    let content: String
    let setup: String
    let punchline: String
    let notes: String
    let isRoast: Bool
    let targetName: String?
    
    var hasStructure: Bool {
        !setup.isEmpty || !punchline.isEmpty
    }
}

// MARK: - Finalize Set Sheet

struct FinalizeSetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var setList: SetList
    
    @State private var estimatedMinutes: Int = 5
    @State private var venueName: String = ""
    @State private var hasPerformanceDate: Bool = false
    @State private var performanceDate: Date = Date()
    @State private var showError = false
    @State private var errorMessage = ""
    
    /// Safe access to setList name
    private var safeSetName: String {
        guard setList.modelContext != nil else { return "Set" }
        return setList.name.isEmpty ? "Set" : setList.name
    }
    
    /// Safe total item count
    private var safeTotalCount: Int {
        guard setList.modelContext != nil else { return 0 }
        return setList.totalItemCount
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(safeSetName)
                            .font(.title2.bold())
                        Text("\(safeTotalCount) joke\(safeTotalCount == 1 ? "" : "s") in this set")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Performance Details") {
                    Stepper("Estimated Time: \(estimatedMinutes) min", value: $estimatedMinutes, in: 1...120)
                    
                    TextField("Venue/Event Name (optional)", text: $venueName)
                    
                    Toggle("Set Performance Date", isOn: $hasPerformanceDate)
                    
                    if hasPerformanceDate {
                        DatePicker("Performance Date", selection: $performanceDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("What Finalizing Does", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "lock.fill", text: "Locks set order - no accidental changes")
                            FeatureRow(icon: "eye.fill", text: "Clean live performance view")
                            FeatureRow(icon: "display", text: "Large text, swipe navigation")
                            FeatureRow(icon: "sun.max.fill", text: "Screen stays awake on stage")
                            FeatureRow(icon: "timer", text: "Built-in performance timer")
                        }
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text("You can always unfinalize later to make edits.")
                }
            }
            .navigationTitle("Finalize Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finalize") {
                        finalizeSet()
                    }
                    .fontWeight(.semibold)
                    .disabled(safeTotalCount == 0)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func finalizeSet() {
        // Safety check
        guard setList.modelContext != nil else {
            errorMessage = "Set list is no longer available."
            showError = true
            return
        }
        
        setList.finalize(
            estimatedMinutes: estimatedMinutes,
            venueName: venueName,
            performanceDate: hasPerformanceDate ? performanceDate : nil
        )
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Could not finalize set: \(error.localizedDescription)"
            showError = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Finalized Set Badge

struct FinalizedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
            Text("READY")
                .font(.caption2.bold())
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue)
        .clipShape(Capsule())
    }
}

// MARK: - Joke List Row (for ALL JOKES list in performance)

struct JokeListRow: View {
    let index: Int
    let item: PerformanceItem
    let isCurrentIndex: Bool
    let fontSize: CGFloat
    let onTap: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row - always visible
            Button {
                onTap()
            } label: {
                HStack(spacing: 12) {
                    // Number badge
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(isCurrentIndex ? .black : .white)
                        .frame(width: 32, height: 32)
                        .background(isCurrentIndex ? Color.blue : Color.white.opacity(0.2))
                        .clipShape(Circle())
                    
                    // Joke preview
                    VStack(alignment: .leading, spacing: 4) {
                        if item.isRoast, let target = item.targetName {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                Text(target.uppercased())
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Text(item.content.prefix(80) + (item.content.count > 80 ? "..." : ""))
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 6) {
                        // Current indicator
                        if isCurrentIndex {
                            Text("NOW")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        // Expand button for roasts with structure
                        if item.hasStructure {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isCurrentIndex ? Color.blue.opacity(0.15) : Color.clear)
            }
            
            // Expanded details for roasts
            if isExpanded && item.hasStructure {
                VStack(alignment: .leading, spacing: 16) {
                    if !item.setup.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SETUP")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                            Text(item.setup)
                                .font(.system(size: fontSize - 4))
                                .foregroundColor(.white.opacity(0.95))
                                .lineSpacing(4)
                        }
                    }
                    
                    if !item.punchline.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PUNCHLINE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                            Text(item.punchline)
                                .font(.system(size: fontSize + 2, weight: .semibold))
                                .foregroundColor(.white)
                                .lineSpacing(4)
                        }
                    }
                    
                    if !item.notes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text(item.notes)
                                .font(.system(size: 12))
                                .foregroundColor(.blue.opacity(0.9))
                                .italic()
                        }
                    }
                    
                    // Tap to go button
                    Button {
                        onTap()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("GO TO THIS JOKE")
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(item.isRoast ? .blue : Color.blue)
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 16)
                .background(Color.white.opacity(0.05))
            }
        }
    }
}

// MARK: - Backup Joke Row (for live performance backup list)

struct BackupJokeRow: View {
    let content: String
    let isRoast: Bool
    let targetName: String?
    let fontSize: CGFloat
    let setup: String
    let punchline: String
    let notes: String
    
    @State private var isExpanded = false
    
    init(content: String, isRoast: Bool, targetName: String?, fontSize: CGFloat, setup: String = "", punchline: String = "", notes: String = "") {
        self.content = content
        self.isRoast = isRoast
        self.targetName = targetName
        self.fontSize = fontSize
        self.setup = setup
        self.punchline = punchline
        self.notes = notes
    }
    
    private var hasStructure: Bool {
        !setup.isEmpty || !punchline.isEmpty
    }
    
    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    // Roast indicator
                    if isRoast {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                    
                    // Target name if roast
                    if let target = targetName {
                        Text(target.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                // Joke content
                if isExpanded {
                    // Full content - big and readable
                    VStack(alignment: .leading, spacing: 16) {
                        if hasStructure {
                            // Structured roast with setup/punchline
                            if !setup.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("SETUP")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.blue)
                                    Text(setup)
                                        .font(.system(size: fontSize))
                                        .foregroundColor(.white.opacity(0.95))
                                        .lineSpacing(6)
                                }
                            }
                            
                            if !punchline.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("PUNCHLINE")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.blue)
                                    Text(punchline)
                                        .font(.system(size: fontSize + 2, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineSpacing(6)
                                }
                            }
                            
                            // Also show full content if different
                            if !content.isEmpty && content != setup && content != punchline {
                                Text(content)
                                    .font(.system(size: fontSize - 2))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineSpacing(4)
                            }
                        } else {
                            // Just the content
                            Text(content)
                                .font(.system(size: fontSize))
                                .foregroundColor(.white)
                                .lineSpacing(6)
                        }
                        
                        // Notes if any
                        if !notes.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                Text(notes)
                                    .font(.system(size: max(12, fontSize - 8)))
                                    .foregroundColor(.blue.opacity(0.9))
                                    .italic()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } else {
                    // Preview only
                    Text(content.prefix(100) + (content.count > 100 ? "..." : ""))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isExpanded ? Color.white.opacity(0.1) : Color.clear)
        }
    }
}

// MARK: - Target Section (for roast targets overlay)
// Shows Opening Roast slots (configurable per target) with their backup roasts underneath each

struct TargetSection: View {
    let targetName: String
    let inSetRoasts: [PerformanceItem]
    let backupRoasts: [RoastJoke]
    let allRoastsForTarget: [RoastJoke] // All roasts for this target to check opening/backup status
    let openingRoastCount: Int // Number of opening roast slots (configurable per target)
    let fontSize: CGFloat
    let onJumpToRoast: (PerformanceItem) -> Void
    
    @State private var isExpanded = true
    
    /// Get opening roasts (marked as opening, up to openingRoastCount)
    private var openingRoasts: [(item: PerformanceItem?, joke: RoastJoke?)] {
        // Find opening roasts from all roasts for this target
        let openingJokes = allRoastsForTarget.filter { $0.isOpeningRoast && !$0.isDeleted }
            .sorted { $0.displayOrder < $1.displayOrder }
        
        // Create slots based on openingRoastCount
        var slots: [(item: PerformanceItem?, joke: RoastJoke?)] = []
        
        for i in 0..<openingRoastCount {
            if i < openingJokes.count {
                let joke = openingJokes[i]
                // Find matching performance item if in set
                let matchingItem = inSetRoasts.first { $0.id == joke.id }
                slots.append((item: matchingItem, joke: joke))
            } else {
                slots.append((item: nil, joke: nil))
            }
        }
        
        return slots
    }
    
    /// Get backup roasts for a specific opening roast
    private func backupsFor(openingID: UUID) -> [RoastJoke] {
        allRoastsForTarget.filter { 
            $0.parentOpeningRoastID == openingID && !$0.isDeleted 
        }.sorted { $0.displayOrder < $1.displayOrder }
    }
    
    /// Get unassigned roasts (not opening and no parent)
    private var unassignedRoasts: [RoastJoke] {
        allRoastsForTarget.filter { 
            !$0.isOpeningRoast && $0.parentOpeningRoastID == nil && !$0.isDeleted 
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Target header - always visible
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Flame icon
                    Image(systemName: "flame.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    
                    // Target name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(targetName.uppercased())
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 8) {
                            let openingCount = openingRoasts.compactMap { $0.joke }.count
                            Text("\(openingCount)/\(openingRoastCount) openers")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            
                            let totalBackups = openingRoasts.compactMap { $0.joke }.reduce(0) { 
                                $0 + backupsFor(openingID: $1.id).count 
                            }
                            if totalBackups > 0 {
                                Text("\(totalBackups) backup\(totalBackups == 1 ? "" : "s")")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding()
                .background(.blue.opacity(0.15))
            }
            
            // Opening Roast Sections (based on openingRoastCount) with their backups
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(0..<openingRoastCount, id: \.self) { index in
                        OpeningRoastSection(
                            slotNumber: index + 1,
                            openingItem: openingRoasts[index].item,
                            openingJoke: openingRoasts[index].joke,
                            backupJokes: openingRoasts[index].joke.map { backupsFor(openingID: $0.id) } ?? [],
                            inSetRoasts: inSetRoasts,
                            fontSize: fontSize,
                            onJumpToRoast: onJumpToRoast
                        )
                    }
                    
                    // Show unassigned roasts if any
                    if !unassignedRoasts.isEmpty {
                        UnassignedRoastsSection(
                            roasts: unassignedRoasts,
                            inSetRoasts: inSetRoasts,
                            fontSize: fontSize,
                            onJumpToRoast: onJumpToRoast
                        )
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Opening Roast Section (one of 3 slots with its backups)

struct OpeningRoastSection: View {
    let slotNumber: Int
    let openingItem: PerformanceItem?
    let openingJoke: RoastJoke?
    let backupJokes: [RoastJoke]
    let inSetRoasts: [PerformanceItem]
    let fontSize: CGFloat
    let onJumpToRoast: (PerformanceItem) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Opening Roast Header
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Slot number badge
                    Text("\(slotNumber)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(openingJoke != nil ? .black : .white.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(openingJoke != nil ? Color.blue : Color.white.opacity(0.1))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OPENING ROAST \(slotNumber)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                        
                        if let joke = openingJoke {
                            Text(joke.content.prefix(50) + (joke.content.count > 50 ? "..." : ""))
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        } else {
                            Text("Not assigned")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.3))
                                .italic()
                        }
                    }
                    
                    Spacer()
                    
                    // Backup count badge
                    if !backupJokes.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 10))
                            Text("\(backupJokes.count)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(6)
                    }
                    
                    // Expand indicator
                    if openingJoke != nil || !backupJokes.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.08))
            }
            
            // Expanded content: Opening roast details + backup roasts
            if isExpanded {
                VStack(spacing: 0) {
                    // The opening roast itself
                    if let joke = openingJoke {
                        OpeningRoastDetailRow(
                            item: openingItem,
                            joke: joke,
                            fontSize: fontSize,
                            onJump: openingItem.map { item in { onJumpToRoast(item) } }
                        )
                    }
                    
                    // Backup roasts for this opening
                    if !backupJokes.isEmpty {
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 10))
                                Text("BACKUPS")
                                    .font(.system(size: 10, weight: .bold))
                                Spacer()
                            }
                            .foregroundColor(.blue.opacity(0.8))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.05))
                            
                            ForEach(backupJokes) { backup in
                                BackupRoastDetailRow(
                                    joke: backup,
                                    matchingItem: inSetRoasts.first { $0.id == backup.id },
                                    fontSize: fontSize,
                                    onJump: inSetRoasts.first { $0.id == backup.id }.map { item in { onJumpToRoast(item) } }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Opening Roast Detail Row

struct OpeningRoastDetailRow: View {
    let item: PerformanceItem?
    let joke: RoastJoke
    let fontSize: CGFloat
    let onJump: (() -> Void)?
    
    @State private var isExpanded = false
    
    private var hasStructure: Bool {
        !joke.setup.isEmpty || !joke.punchline.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // In-set indicator
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    
                    // Preview
                    Text(joke.content.prefix(80) + (joke.content.count > 80 ? "..." : ""))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(isExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    // In set badge
                    if item != nil {
                        Text("IN SET")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.05))
            }
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Structure if available
                    if hasStructure {
                        if !joke.setup.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SETUP")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.blue)
                                Text(joke.setup)
                                    .font(.system(size: fontSize))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineSpacing(6)
                            }
                        }
                        
                        if !joke.punchline.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PUNCHLINE")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.blue)
                                Text(joke.punchline)
                                    .font(.system(size: fontSize + 2, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineSpacing(6)
                            }
                        }
                    } else {
                        // Just full content
                        Text(joke.content)
                            .font(.system(size: fontSize))
                            .foregroundColor(.white)
                            .lineSpacing(6)
                    }
                    
                    // Notes
                    if !joke.performanceNotes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text(joke.performanceNotes)
                                .font(.system(size: max(12, fontSize - 8)))
                                .foregroundColor(.blue.opacity(0.9))
                                .italic()
                        }
                    }
                    
                    // Jump button (only for in-set roasts)
                    if let jumpAction = onJump {
                        Button {
                            jumpAction()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("GO TO THIS ROAST")
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.05))
            }
        }
    }
}

// MARK: - Backup Roast Detail Row

struct BackupRoastDetailRow: View {
    let joke: RoastJoke
    let matchingItem: PerformanceItem?
    let fontSize: CGFloat
    let onJump: (() -> Void)?
    
    @State private var isExpanded = false
    
    private var hasStructure: Bool {
        !joke.setup.isEmpty || !joke.punchline.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Backup indicator
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    
                    // Preview
                    Text(joke.content.prefix(70) + (joke.content.count > 70 ? "..." : ""))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(isExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.03))
            }
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    // Structure if available
                    if hasStructure {
                        if !joke.setup.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SETUP")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.blue)
                                Text(joke.setup)
                                    .font(.system(size: fontSize - 2))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineSpacing(5)
                            }
                        }
                        
                        if !joke.punchline.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PUNCHLINE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.blue)
                                Text(joke.punchline)
                                    .font(.system(size: fontSize, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineSpacing(5)
                            }
                        }
                    } else {
                        // Just full content
                        Text(joke.content)
                            .font(.system(size: fontSize - 2))
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(5)
                    }
                    
                    // Notes
                    if !joke.performanceNotes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            Text(joke.performanceNotes)
                                .font(.system(size: max(11, fontSize - 10)))
                                .foregroundColor(.blue.opacity(0.9))
                                .italic()
                        }
                    }
                    
                    // Jump button if in set
                    if let jumpAction = onJump {
                        Button {
                            jumpAction()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("GO TO THIS BACKUP")
                                    .fontWeight(.medium)
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(6)
                        }
                    } else {
                        // Not in set indicator
                        HStack {
                            Image(systemName: "tray.full.fill")
                            Text("Not in set")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.blue.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.03))
            }
        }
    }
}

// MARK: - Unassigned Roasts Section

struct UnassignedRoastsSection: View {
    let roasts: [RoastJoke]
    let inSetRoasts: [PerformanceItem]
    let fontSize: CGFloat
    let onJumpToRoast: (PerformanceItem) -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    
                    Text("UNASSIGNED ROASTS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                    
                    Text("(\(roasts.count))")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.7))
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
            }
            
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(roasts) { roast in
                        BackupRoastDetailRow(
                            joke: roast,
                            matchingItem: inSetRoasts.first { $0.id == roast.id },
                            fontSize: fontSize,
                            onJump: inSetRoasts.first { $0.id == roast.id }.map { item in { onJumpToRoast(item) } }
                        )
                    }
                }
            }
        }
    }
}
