//
//  HomeView.swift
//  thebitbinder
//
//  A calm launchpad — writer's desk + set-prep board.
//  Gets a comic back into material fast.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - HomeView

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // Data — filter out soft-deleted items at the query level to reduce memory
    @Query(filter: #Predicate<Joke> { !$0.isDeleted }, sort: \Joke.dateModified, order: .reverse) private var allJokes: [Joke]
    @Query(filter: #Predicate<SetList> { !$0.isDeleted }, sort: \SetList.dateModified, order: .reverse) private var allSets: [SetList]
    @Query(filter: #Predicate<BrainstormIdea> { !$0.isDeleted }, sort: \BrainstormIdea.dateCreated, order: .reverse) private var allIdeas: [BrainstormIdea]
    @Query(filter: #Predicate<Recording> { !$0.isDeleted }, sort: \Recording.dateCreated, order: .reverse) private var allRecordings: [Recording]
    @Query(sort: \ImportBatch.importTimestamp, order: .reverse) private var allImports: [ImportBatch]

    // State
    @State private var searchText = ""
    @State private var showAddJoke = false
    @State private var showBrainstorm = false
    @State private var showVoiceNote = false
    @State private var showTalkToText = false

    @AppStorage("roastModeEnabled") private var roastMode = false

    // Cached derived data — rebuilt via onChange, not on every body render
    @State private var cachedContinueItems: [ContinueItem] = []
    @State private var cachedAttentionItems: [AttentionItem] = []
    @State private var cachedEditedThisWeek: Int = 0
    @State private var cachedStageReadyCount: Int = 0

    // MARK: - Computed data (lightweight only)

    private var activeJokes: [Joke] { allJokes }

    private var activeSets: [SetList] {
        allSets.sorted { $0.dateModified > $1.dateModified }
    }

    private var importsNeedingReview: [ImportBatch] {
        allImports.filter { $0.reviewQueueCount > 0 }
    }

    // Search
    private var isSearching: Bool { !searchText.isEmpty }

    private var universalSearchResults: [HomeSearchResult] {
        guard isSearching else { return [] }
        let q = searchText.lowercased()
        var results: [HomeSearchResult] = []
        let jokes = activeJokes

        // Jokes
        for joke in jokes where
            joke.title.lowercased().contains(q) ||
            joke.content.lowercased().contains(q) ||
            joke.tags.contains(where: { $0.lowercased().contains(q) })
        {
            results.append(HomeSearchResult(
                id: joke.id.uuidString,
                title: joke.title,
                subtitle: String(joke.content.prefix(60)) + (joke.content.count > 60 ? "…" : ""),
                type: .joke,
                icon: "theatermask.and.paintbrush",
                joke: joke
            ))
        }

        // Set lists
        for set in allSets where
            set.name.lowercased().contains(q) ||
            set.notes.lowercased().contains(q)
        {
            let count = set.totalItemCount
            results.append(HomeSearchResult(
                id: set.id.uuidString,
                title: set.name,
                subtitle: "\(count) joke\(count == 1 ? "" : "s")",
                type: .setList,
                icon: "list.bullet.rectangle.portrait",
                setList: set
            ))
        }

        // Recordings
        for rec in allRecordings where
            rec.title.lowercased().contains(q) ||
            (rec.transcription ?? "").lowercased().contains(q)
        {
            results.append(HomeSearchResult(
                id: rec.id.uuidString,
                title: rec.title,
                subtitle: rec.transcription.map { String($0.prefix(60)) + ($0.count > 60 ? "…" : "") } ?? "No transcript",
                type: .recording,
                icon: "waveform.circle",
                recording: rec
            ))
        }

        // Brainstorm ideas
        for idea in allIdeas where idea.content.lowercased().contains(q) {
            results.append(HomeSearchResult(
                id: idea.id.uuidString,
                title: String(idea.content.prefix(50)) + (idea.content.count > 50 ? "…" : ""),
                subtitle: "Brainstorm",
                type: .brainstorm,
                icon: "lightbulb"
            ))
        }

        return Array(results.prefix(10))
    }

    // MARK: - Rebuild cached data (called on appear + onChange)

    private func rebuildCachedData() {
        let jokes = activeJokes

        // Continue items
        var items: [ContinueItem] = []
        for joke in jokes.prefix(3) {
            let status: ContinueItem.Status =
                (joke.difficulty ?? "").lowercased() == "needs rewrite" ? .needsRewrite :
                joke.content.count < 50 ? .draft : .working
            items.append(ContinueItem(
                id: joke.id.uuidString,
                title: joke.title,
                type: .joke,
                status: status,
                lastTouched: joke.dateModified,
                joke: joke
            ))
        }
        if let set = activeSets.first {
            items.append(ContinueItem(
                id: set.id.uuidString,
                title: set.name,
                type: .setList,
                status: .inProgress,
                lastTouched: set.dateModified,
                setList: set
            ))
        }
        if let idea = allIdeas.first {
            items.append(ContinueItem(
                id: idea.id.uuidString,
                title: String(idea.content.prefix(60)) + (idea.content.count > 60 ? "\u{2026}" : ""),
                type: .brainstorm,
                status: .working,
                lastTouched: idea.dateCreated,
                brainstormIdea: idea
            ))
        }
        let imports = importsNeedingReview
        if let batch = imports.first {
            items.append(ContinueItem(
                id: batch.id.uuidString,
                title: batch.sourceFileName.isEmpty ? "Import" : batch.sourceFileName,
                type: .importBatch,
                status: .review,
                lastTouched: batch.importTimestamp,
                detail: "\(batch.reviewQueueCount) items"
            ))
        }
        cachedContinueItems = Array(items.prefix(5))

        // Attention items
        var attention: [AttentionItem] = []
        let reviewCount = imports.reduce(0) { $0 + $1.reviewQueueCount }
        if reviewCount > 0 {
            attention.append(AttentionItem(icon: "doc.text.magnifyingglass", text: "\(reviewCount) imports need review", variant: .warning, targetScreen: .jokes))
        }
        let recCount = allRecordings.filter({ !$0.isProcessed }).count
        if recCount > 0 {
            attention.append(AttentionItem(icon: "waveform.badge.exclamationmark", text: "\(recCount) recordings need transcript cleanup", variant: .warning, targetScreen: .recordings))
        }
        let untagged = jokes.filter({ $0.tags.isEmpty && $0.category == nil }).count
        if untagged > 0 {
            attention.append(AttentionItem(icon: "tag.slash", text: "\(untagged) jokes are untagged", variant: .info, targetScreen: .jokes))
        }
        let rewrite = jokes.filter({ ($0.difficulty ?? "").lowercased() == "needs rewrite" }).count
        if rewrite > 0 {
            attention.append(AttentionItem(icon: "pencil.line", text: "\(rewrite) jokes marked Needs Rewrite", variant: .warning, targetScreen: .jokes))
        }
        cachedAttentionItems = attention

        // Insight stats
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        cachedEditedThisWeek = jokes.filter({ $0.dateModified >= weekAgo }).count
        cachedStageReadyCount = jokes.filter({ $0.isHit }).count
    }

    // MARK: - Body

    var body: some View {
        mainNavigationStack
            .tint(AppTheme.Colors.primaryAction)
            .onAppear { rebuildCachedData() }
            .onChange(of: allJokes.count) { _, _ in rebuildCachedData() }
            .onChange(of: allSets.count) { _, _ in rebuildCachedData() }
            .onChange(of: allIdeas.count) { _, _ in rebuildCachedData() }
            .onChange(of: allRecordings.count) { _, _ in rebuildCachedData() }
            .onChange(of: allImports.count) { _, _ in rebuildCachedData() }
    }

    // MARK: - Main Navigation Stack

    private var mainNavigationStack: some View {
        NavigationStack {
            mainContentZStack
                .navigationBarTitleDisplayMode(.inline)
                .bitBinderToolbar(roastMode: roastMode)
                .sheet(isPresented: $showAddJoke) { AddJokeView() }
                .sheet(isPresented: $showBrainstorm) { AddBrainstormIdeaSheet() }
                .sheet(isPresented: $showVoiceNote) { StandaloneRecordingView() }
                .sheet(isPresented: $showTalkToText) { TalkToTextView(selectedFolder: nil as JokeFolder?) }
        }
    }

    // MARK: - Main Content ZStack

    private var mainContentZStack: some View {
        ZStack {
            AppTheme.Colors.paperCream.ignoresSafeArea()

            if horizontalSizeClass == .regular {
                if verticalSizeClass == .regular {
                    // iPad portrait: two-column with intentional proportions
                    iPadPortraitLayout
                } else {
                    // iPad landscape: three-column workspace
                    iPadLandscapeLayout
                }
            } else {
                // iPhone: optimized single-column
                iPhoneLayout
            }
        }
    }

    // MARK: - My Jokes Shortcut

    private var myJokesShortcut: some View {
        Button {
            NotificationCenter.default.post(
                name: .navigateToScreen,
                object: nil,
                userInfo: ["screen": AppScreen.jokes.rawValue]
            )
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: AppScreen.jokes.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text("My Jokes")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                Spacer()
                Text("\(activeJokes.count)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.Colors.jokesAccent.opacity(0.8))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(AppTheme.Colors.jokesAccent)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(AppTheme.Colors.jokesAccent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .strokeBorder(AppTheme.Colors.jokesAccent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(TouchReactiveStyle(pressedScale: 0.97, hapticStyle: .light))
    }

    // MARK: - iPhone layout (optimized single column)

    private var iPhoneLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                    .padding(.bottom, AppTheme.Spacing.md)

                myJokesShortcut
                    .padding(.bottom, AppTheme.Spacing.xl)

                continueSection
                    .padding(.bottom, AppTheme.Spacing.xl)

                quickCaptureSection
                    .padding(.bottom, AppTheme.Spacing.lg)

                setsSection
                    .padding(.bottom, AppTheme.Spacing.md)

                if !cachedAttentionItems.isEmpty {
                    attentionSection
                        .padding(.bottom, AppTheme.Spacing.md)
                }

                insightStrip
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
    }

    // MARK: - iPad Portrait layout (intentional two-column)

    private var iPadPortraitLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                    .frame(maxWidth: 640) // Tighter header constraint
                    .padding(.bottom, AppTheme.Spacing.md)

                myJokesShortcut
                    .frame(maxWidth: 640)
                    .padding(.bottom, AppTheme.Spacing.xl)

                HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                    // Left column: Continue Working + Needs Attention (narrower)
                    VStack(spacing: AppTheme.Spacing.xl) {
                        continueSection
                        if !cachedAttentionItems.isEmpty {
                            attentionSection
                        }
                    }
                    .frame(maxWidth: 260) // Tighter constraint

                    // Right column: Quick Capture + Sets + Insights (wider)
                    VStack(spacing: AppTheme.Spacing.lg) {
                        quickCaptureSection
                        setsSection
                        insightStrip
                    }
                    .frame(maxWidth: 320) // Tighter constraint
                }
                .frame(maxWidth: 640) // Tighter overall content width
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
        }
    }

    // MARK: - iPad Landscape layout (three-column workspace)

    private var iPadLandscapeLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header spans full width but constrained
                headerSection
                    .frame(maxWidth: 840)
                    .padding(.bottom, AppTheme.Spacing.md)

                myJokesShortcut
                    .frame(maxWidth: 840)
                    .padding(.bottom, AppTheme.Spacing.xl)

                // Three-column workspace layout
                HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                    // Left sidebar: Continue Working
                    VStack(spacing: AppTheme.Spacing.lg) {
                        continueSection
                    }
                    .frame(width: 240) // Tighter fixed width sidebar

                    // Center column: Quick Capture
                    VStack(spacing: AppTheme.Spacing.lg) {
                        quickCaptureSection
                    }
                    .frame(maxWidth: 280) // Tighter width for actions

                    // Right column: Sets + Attention + Insights
                    VStack(spacing: AppTheme.Spacing.md) {
                        setsSection
                        if !cachedAttentionItems.isEmpty {
                            attentionSection
                        }
                        insightStrip
                    }
                    .frame(maxWidth: 300) // Tighter constraint right column
                }
                .frame(maxWidth: 840) // Tighter overall workspace constraint
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Title
            Text("BitBinder")
                .font(AppTheme.Typography.display)
                .foregroundColor(AppTheme.Colors.inkBlack)

            // Search
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.Colors.textTertiary)
                TextField("Search jokes, sets, tags, recordings…", text: $searchText)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.inkBlack)
                if isSearching {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(AppTheme.Colors.paperAged)
            )
            .frame(maxWidth: 480) // Constrain search bar width for professionalism

            // Search results
            if isSearching {
                searchResultsList
                    .frame(maxWidth: 480) // Constrain search results width
            }
        }
        .padding(.top, AppTheme.Spacing.md)
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        VStack(spacing: 0) {
            if universalSearchResults.isEmpty {
                HStack {
                    Text("No results for \u{201C}\(searchText)\u{201D}")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.md)
            } else {
                ForEach(universalSearchResults) { result in
                    searchResultRow(result)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(_ result: HomeSearchResult) -> some View {
        Group {
            switch result.type {
            case .joke:
                if let joke = result.joke {
                    NavigationLink(destination: JokeDetailView(joke: joke)) {
                        searchRowContent(result)
                    }
                }
            case .setList:
                if let setList = result.setList {
                    NavigationLink(destination: SetListDetailView(setList: setList)) {
                        searchRowContent(result)
                    }
                }
            case .recording:
                if let recording = result.recording {
                    NavigationLink(destination: RecordingDetailView(recording: recording)) {
                        searchRowContent(result)
                    }
                }
            case .brainstorm:
                Button {
                    NotificationCenter.default.post(
                        name: .navigateToScreen,
                        object: nil,
                        userInfo: ["screen": AppScreen.brainstorm.rawValue]
                    )
                } label: {
                    searchRowContent(result)
                }
            }
        }
    }

    private func searchRowContent(_ result: HomeSearchResult) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: result.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.Colors.primaryAction)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(AppTheme.Typography.callout)
                    .foregroundColor(AppTheme.Colors.inkBlack)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(result.type.label)
                        .font(AppTheme.Typography.caption2)
                        .foregroundColor(AppTheme.Colors.primaryAction.opacity(0.7))

                    Text(result.subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Continue Working

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            BitBinderSectionHeader(title: "Continue Working")

            if cachedContinueItems.isEmpty {
                BitBinderCard(elevation: .low) {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        Text("Nothing recent — write something!")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        Spacer()
                    }
                    .padding(AppTheme.Spacing.md)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(cachedContinueItems) { item in
                        continueItemLink(item)
                    }
                }
            }
        }
    }

    /// Wraps each ContinueWorkingRow in the correct NavigationLink
    @ViewBuilder
    private func continueItemLink(_ item: ContinueItem) -> some View {
        switch item.type {
        case .joke:
            if let joke = item.joke {
                NavigationLink(destination: JokeDetailView(joke: joke)) {
                    ContinueWorkingRow(item: item)
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.98, hapticStyle: nil))
            }
        case .setList:
            if let setList = item.setList {
                NavigationLink(destination: SetListDetailView(setList: setList)) {
                    ContinueWorkingRow(item: item)
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.98, hapticStyle: nil))
            }
        case .brainstorm:
            Button {
                NotificationCenter.default.post(
                    name: .navigateToScreen,
                    object: nil,
                    userInfo: ["screen": AppScreen.brainstorm.rawValue]
                )
            } label: {
                ContinueWorkingRow(item: item)
            }
            .buttonStyle(TouchReactiveStyle(pressedScale: 0.98, hapticStyle: nil))
        case .importBatch:
            NavigationLink(destination: ImportBatchHistoryView()) {
                ContinueWorkingRow(item: item)
            }
            .buttonStyle(TouchReactiveStyle(pressedScale: 0.98, hapticStyle: nil))
        }
    }

    // MARK: - Quick Capture

    private var quickCaptureSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            BitBinderSectionHeader(title: "Quick Capture")

            VStack(spacing: AppTheme.Spacing.sm) {
                // Primary action — New Joke (full width, prominent)
                Button { showAddJoke = true } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("New Joke")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(AppTheme.Colors.primaryAction)
                    )
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.97, hapticStyle: .light))

                // Talk-to-Text Joke — prominent full-width button
                Button { showTalkToText = true } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .medium))
                        Text("Talk-to-Text Joke")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.Colors.primaryAction)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(AppTheme.Colors.surfaceElevated)
                            .shadow(color: AppTheme.Shadows.sm.color, radius: AppTheme.Shadows.sm.radius, x: 0, y: AppTheme.Shadows.sm.y)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .strokeBorder(AppTheme.Colors.primaryAction.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.97, hapticStyle: .light))

                // Secondary actions — horizontal row
                HStack(spacing: AppTheme.Spacing.sm) {
                    QuickCaptureButton(icon: "lightbulb", label: "Brainstorm", color: AppTheme.Colors.brainstormAccent) {
                        showBrainstorm = true
                    }
                    QuickCaptureButton(icon: "mic.fill", label: "Record", color: AppTheme.Colors.recordingsAccent) {
                        showVoiceNote = true
                    }
                }
            }
        }
    }

    // MARK: - Sets in Progress

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            BitBinderSectionHeader(title: "Sets in Progress")

            if activeSets.isEmpty {
                BitBinderCard(elevation: .low) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        Text("No set lists yet")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        Spacer()
                    }
                    .padding(AppTheme.Spacing.md)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(activeSets.prefix(3)) { set in
                        NavigationLink(destination: SetListDetailView(setList: set)) {
                            SetProgressRow(setList: set, allJokes: activeJokes)
                        }
                        .buttonStyle(TouchReactiveStyle(pressedScale: 0.98, hapticStyle: nil))
                    }
                }
            }
        }
    }

    // MARK: - Needs Attention

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            BitBinderSectionHeader(title: "Needs Attention")

            BitBinderCard(elevation: .low) {
                VStack(spacing: 0) {
                    ForEach(cachedAttentionItems) { item in
                        attentionRow(item)

                        if item.id != cachedAttentionItems.last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func attentionRow(_ item: AttentionItem) -> some View {
        if let screen = item.targetScreen {
            Button {
                // Post a notification that MainTabView can observe to switch screens
                NotificationCenter.default.post(
                    name: .navigateToScreen,
                    object: nil,
                    userInfo: ["screen": screen.rawValue]
                )
            } label: {
                attentionRowContent(item)
            }
            .buttonStyle(TouchReactiveStyle(pressedScale: 0.98, hapticStyle: nil))
        } else {
            attentionRowContent(item)
        }
    }

    private func attentionRowContent(_ item: AttentionItem) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(item.variant == .warning ? AppTheme.Colors.warning : AppTheme.Colors.primaryAction)
                .frame(width: 22)

            Text(item.text)
                .font(AppTheme.Typography.subheadline)
                .foregroundColor(AppTheme.Colors.textPrimary)

            Spacer()

            if item.targetScreen != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 10)
    }

    // MARK: - Insight Strip

    private var insightStrip: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            BitBinderSectionHeader(title: "This Week")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    InsightChip(value: "\(cachedEditedThisWeek)", label: "edited")
                    InsightChip(value: "\(activeSets.count)", label: activeSets.count == 1 ? "set" : "sets")
                    if importsNeedingReview.count > 0 {
                        InsightChip(value: "\(importsNeedingReview.reduce(0) { $0 + $1.reviewQueueCount })", label: "awaiting review")
                    }
                    InsightChip(value: "\(cachedStageReadyCount)", label: "stage-ready")
                }
            }
        }
    }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToScreen = Notification.Name("navigateToScreen")
}

// MARK: - Supporting Types

struct ContinueItem: Identifiable {
    let id: String
    let title: String
    let type: ItemType
    let status: Status
    let lastTouched: Date
    var detail: String? = nil

    // References to actual model objects for navigation
    var joke: Joke? = nil
    var setList: SetList? = nil
    var brainstormIdea: BrainstormIdea? = nil

    enum ItemType: String {
        case joke = "Joke"
        case setList = "Set List"
        case brainstorm = "Brainstorm"
        case importBatch = "Import"
    }

    enum Status: String {
        case working = "Working"
        case draft = "Draft"
        case needsRewrite = "Needs Rewrite"
        case inProgress = "In Progress"
        case review = "Review"
        case ready = "Ready"
    }
}

struct AttentionItem: Identifiable {
    var id: String { text }
    let icon: String
    let text: String
    let variant: Variant
    var targetScreen: AppScreen? = nil

    enum Variant {
        case warning, info
    }
}

struct HomeSearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let type: SearchResultType
    let icon: String

    // Model references for navigation
    var joke: Joke? = nil
    var setList: SetList? = nil
    var recording: Recording? = nil

    enum SearchResultType {
        case joke, setList, recording, brainstorm

        var label: String {
            switch self {
            case .joke:       return "Joke"
            case .setList:    return "Set List"
            case .recording:  return "Recording"
            case .brainstorm: return "Brainstorm"
            }
        }
    }
}

// MARK: - Continue Working Row

private struct ContinueWorkingRow: View {
    let item: ContinueItem

    private var statusColor: Color {
        switch item.status {
        case .working, .inProgress: return AppTheme.Colors.primaryAction
        case .draft:                return AppTheme.Colors.textTertiary
        case .needsRewrite:         return AppTheme.Colors.warning
        case .review:               return AppTheme.Colors.warning
        case .ready:                return AppTheme.Colors.success
        }
    }

    private var typeIcon: String {
        switch item.type {
        case .joke:        return "theatermask.and.paintbrush"
        case .setList:     return "list.bullet.rectangle.portrait"
        case .brainstorm:  return "lightbulb"
        case .importBatch: return "square.and.arrow.down"
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            // Type icon
            Image(systemName: typeIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.Colors.primaryAction)
                .frame(width: 28, height: 28)

            // Title + meta line
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(AppTheme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.inkBlack)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(item.status.rawValue)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textTertiary)

                    if let detail = item.detail {
                        Text("• \(detail)")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
            }

            Spacer()

            // Relative time
            Text(item.lastTouched.relativeHomeLabel)
                .font(AppTheme.Typography.caption2)
                .foregroundColor(AppTheme.Colors.textTertiary)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Colors.surfaceElevated)
                .shadow(color: AppTheme.Shadows.md.color, radius: AppTheme.Shadows.md.radius, x: 0, y: AppTheme.Shadows.md.y)
        )
    }
}

// MARK: - Quick Capture Button

private struct QuickCaptureButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.Colors.inkBlack)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64) // Reduced from 72 for tighter feel
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(AppTheme.Colors.surfaceElevated)
                    .shadow(color: AppTheme.Shadows.sm.color, radius: AppTheme.Shadows.sm.radius, x: 0, y: AppTheme.Shadows.sm.y)
            )
        }
        .buttonStyle(TouchReactiveStyle(pressedScale: 0.96, hapticStyle: .light))
    }
}

// MARK: - Set Progress Row

private struct SetProgressRow: View {
    let setList: SetList
    let allJokes: [Joke]

    private var jokeCount: Int {
        setList.totalItemCount
    }

    /// Rough runtime estimate: ~45 seconds per joke
    private var estimatedRuntime: String {
        let seconds = jokeCount * 45
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    var body: some View {
        BitBinderCard(elevation: .low) {
            HStack(spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(setList.name)
                        .font(AppTheme.Typography.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.Colors.inkBlack)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label("\(jokeCount) jokes", systemImage: "theatermask.and.paintbrush")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.textTertiary)

                        Label(estimatedRuntime, systemImage: "clock")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }

                Spacer()

                Text(setList.dateModified.relativeHomeLabel)
                    .font(AppTheme.Typography.caption2)
                    .foregroundColor(AppTheme.Colors.textTertiary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Insight Chip

private struct InsightChip: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.Colors.primaryAction)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(AppTheme.Colors.primaryAction.opacity(0.08))
        )
    }
}

// MARK: - Date helper

extension Date {
    var relativeHomeLabel: String {
        let cal = Calendar.current
        let now = Date()
        let diff = cal.dateComponents([.minute, .hour, .day], from: self, to: now)

        if let d = diff.day, d >= 2 {
            return "\(d)d ago"
        } else if let d = diff.day, d == 1 {
            return "Yesterday"
        } else if let h = diff.hour, h >= 1 {
            return "\(h)h ago"
        } else if let m = diff.minute, m >= 1 {
            return "\(m)m ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(for: [
            Joke.self, SetList.self, BrainstormIdea.self,
            Recording.self, ImportBatch.self
        ], inMemory: true)
}
