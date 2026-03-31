//
//  SmartImportReviewView.swift
//  thebitbinder
//
//  Interactive joke-by-joke import review with swipe cards.
//  Accept / Reject / Edit / Send to Brainstorm
//

import SwiftUI
import SwiftData

struct SmartImportReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ImportReviewViewModel()
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    let importResult: ImportPipelineResult
    let selectedFolder: JokeFolder?
    let onComplete: (() -> Void)?
    
    @State private var showingEditSheet = false
    @State private var dragOffset: CGSize = .zero
    @State private var showingSaveConfirmation = false
    @State private var savedCount = 0
    @State private var brainstormCount = 0
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showSwipeTutorial = false
    @State private var showingCancelConfirmation = false
    @State private var showUndoBanner = false
    @State private var lastUndoAction: (index: Int, previousAction: ReviewAction)? = nil
    @AppStorage("hasSeenImportSwipeTutorial") private var hasSeenSwipeTutorial = false
    
    init(importResult: ImportPipelineResult, selectedFolder: JokeFolder? = nil, onComplete: (() -> Void)? = nil) {
        self.importResult = importResult
        self.selectedFolder = selectedFolder
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress bar
                    progressSection
                    
                    // GagGrabber rate-limit banner
                    if viewModel.rateLimitError != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundColor(.white)
                            Text(viewModel.rateLimitError!.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(0.9))
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    }
                    
                    // Auto-accepted summary banner
                    if viewModel.autoAcceptedCount > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("\(viewModel.autoAcceptedCount) joke\(viewModel.autoAcceptedCount == 1 ? "" : "s") auto-accepted (high confidence)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.Colors.success.opacity(0.85))
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    }
                    
                    // Prominent "Accept All" when there are pending items
                    if viewModel.pendingCount > 0 {
                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            viewModel.approveAll()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                Text("Accept All \(viewModel.pendingCount) Remaining")
                                    .font(.subheadline.bold())
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    }
                    
                    if viewModel.reviewItems.isEmpty {
                        emptyState
                    } else if viewModel.allItemsReviewed {
                        // All reviewed (including auto-accepted)
                        allReviewedState
                    } else if let current = viewModel.currentItem {
                        // Source file context header
                        if viewModel.pendingCount > 0 {
                            importContextHeader
                        }
                        
                        // Card area
                        Spacer()
                        jokeCard(current)
                            .offset(dragOffset)
                            .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                            .gesture(swipeGesture)
                            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.7), value: dragOffset)
                        Spacer()
                        
                        // Undo banner
                        if viewModel.canUndo {
                            undoBanner
                        }
                        
                        // Action buttons
                        actionButtonRow
                        
                        // Navigation
                        navigationRow
                    } else {
                        // All reviewed
                        allReviewedState
                    }
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                roastMode ? AnyShapeStyle(AppTheme.Colors.roastSurface) : AnyShapeStyle(AppTheme.Colors.paperCream),
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        let hasReviewedAnything = viewModel.reviewItems.contains { $0.action != .pending }
                        if hasReviewedAnything {
                            showingCancelConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("✅ Approve All Remaining") { viewModel.approveAll() }
                        Button("❌ Reject All Remaining") { viewModel.rejectAll() }
                        Divider()
                        Button("Save & Finish") {
                            Task {
                                await finishAndSave()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let current = viewModel.currentItem {
                    editSheet(for: current)
                }
            }
            .alert("Import Complete! 🎉", isPresented: $showingSaveConfirmation) {
                Button("Done") {
                    onComplete?()
                    dismiss()
                }
            } message: {
                let jokeWord = savedCount == 1 ? "joke" : "jokes"
                let ideaWord = brainstormCount == 1 ? "idea" : "ideas"
                if brainstormCount > 0 {
                    Text("Successfully saved \(savedCount) \(jokeWord) to your collection and sent \(brainstormCount) \(ideaWord) to Brainstorm. Your material is growing!")
                } else {
                    Text("Successfully saved \(savedCount) \(jokeWord) to your collection. Head to Jokes to see your new material!")
                }
            }
            .alert("Couldn't Save Jokes", isPresented: $showingSaveError) {
                Button("Try Again") {
                    Task { await finishAndSave() }
                }
                Button("Discard", role: .destructive) {
                    modelContext.rollback()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(saveErrorMessage)\n\nYour imported jokes haven't been lost — tap \"Try Again\" to retry saving them.")
            }
            .alert("Discard Import?", isPresented: $showingCancelConfirmation) {
                Button("Save & Finish") {
                    Task { await finishAndSave() }
                }
                Button("Discard", role: .destructive) {
                    dismiss()
                }
                Button("Keep Reviewing", role: .cancel) { }
            } message: {
                let approved = viewModel.reviewItems.filter { $0.action == .approved }.count
                if approved > 0 {
                    Text("You've accepted \(approved) joke\(approved == 1 ? "" : "s"). Discard your review or save what you have so far?")
                } else {
                    Text("You've started reviewing this import. Are you sure you want to discard it?")
                }
            }
        }
        .onAppear {
            viewModel.loadAllItems(from: importResult)
            if !hasSeenSwipeTutorial && !viewModel.reviewItems.isEmpty {
                showSwipeTutorial = true
            }
        }
        .interactiveDismissDisabled()
        .overlay {
            if showSwipeTutorial {
                swipeTutorialOverlay
            }
        }
    }
    
    // MARK: - Import Context Header
    
    private var importContextHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14))
                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("GagGrabber found \(viewModel.reviewItems.count) joke\(viewModel.reviewItems.count == 1 ? "" : "s") in **\(importResult.sourceFile)**")
                    .font(.system(size: 12))
                    .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                
                if viewModel.pendingCount < viewModel.reviewItems.count {
                    Text("\(viewModel.pendingCount) left to review")
                        .font(.system(size: 11))
                        .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                        .opacity(0.08)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            // Counts
            HStack(spacing: 16) {
                Text(viewModel.summaryText)
                    .font(.caption)
                    .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                Spacer()
                // GagGrabber daily budget indicator
                Label(viewModel.gagGrabberStatus.shortStatusText, systemImage: viewModel.gagGrabberStatus.statusIcon)
                    .font(.caption2)
                    .foregroundColor(viewModel.gagGrabberStatus.statusColor)
                Text(viewModel.progressText)
                    .font(.caption.bold())
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.textPrimary)
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(roastMode ? Color.white.opacity(0.1) : AppTheme.Colors.paperDeep)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
                        .frame(width: geo.size.width * progressFraction)
                        .animation(.easeInOut(duration: 0.3), value: progressFraction)
                }
            }
            .frame(height: 6)
            
            // Mini dot indicators for reviewed status
            miniDotIndicators
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var progressFraction: CGFloat {
        guard !viewModel.reviewItems.isEmpty else { return 0 }
        let reviewed = viewModel.reviewItems.filter { $0.action != .pending }.count
        return CGFloat(reviewed) / CGFloat(viewModel.reviewItems.count)
    }
    
    private var miniDotIndicators: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.reviewItems.enumerated()), id: \.element.id) { index, item in
                    Circle()
                        .fill(dotColor(for: item, isActive: index == viewModel.currentIndex))
                        .frame(width: index == viewModel.currentIndex ? 10 : 6,
                               height: index == viewModel.currentIndex ? 10 : 6)
                        .onTapGesture { viewModel.goToItem(at: index) }
                }
            }
        }
    }
    
    private func dotColor(for item: ImportReviewItem, isActive: Bool) -> Color {
        if isActive {
            return roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction
        }
        switch item.action {
        case .approved: return AppTheme.Colors.success
        case .rejected: return AppTheme.Colors.error.opacity(0.5)
        case .sendToBrainstorm: return AppTheme.Colors.brainstormAccent
        case .needsSplitting: return AppTheme.Colors.warning
        case .pending: return roastMode ? .white.opacity(0.2) : AppTheme.Colors.textTertiary.opacity(0.4)
        }
    }
    
    // MARK: - Joke Card
    
    private func jokeCard(_ item: ImportReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Confidence badge
            HStack {
                confidenceBadge(item.originalJoke.confidence)
                Spacer()
                Text("Page \(item.originalJoke.sourceMetadata.pageNumber)")
                    .font(.caption)
                    .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
            }
            
            // Title
            if !item.editedTitle.isEmpty {
                Text(item.editedTitle)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
            }
            
            // Body
            ScrollView {
                Text(item.editedBody)
                    .font(.system(size: 16, design: .serif))
                    .foregroundColor(roastMode ? .white.opacity(0.9) : AppTheme.Colors.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Tags
            if !item.editedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.editedTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(
                                        roastMode ? AppTheme.Colors.roastAccent.opacity(0.2) : AppTheme.Colors.brand.opacity(0.1)
                                    )
                                )
                                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
                        }
                    }
                }
            }
            
            // Swipe hints
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "hand.point.left.fill")
                        .font(.system(size: 10))
                    Text("Skip")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(AppTheme.Colors.error.opacity(0.5))
                
                Spacer()
                
                Text("or use buttons below")
                    .font(.system(size: 10))
                    .foregroundColor(roastMode ? .white.opacity(0.25) : AppTheme.Colors.textTertiary.opacity(0.5))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("Keep")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "hand.point.right.fill")
                        .font(.system(size: 10))
                }
                .foregroundColor(AppTheme.Colors.success.opacity(0.5))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: 400)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                .shadow(radius: abs(dragOffset.width) > 30 ? 12 : 6, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .inset(by: 1.5)
                .stroke(swipeBorderColor, lineWidth: 3)
        )
        .overlay(alignment: .center) {
            // Swipe feedback overlay
            let absWidth = Double(abs(dragOffset.width))
            if absWidth > 60 {
                Text(dragOffset.width > 0 ? "✅" : "❌")
                    .font(.system(size: 60))
                    .opacity(min(absWidth / 120.0, 1.0))
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var swipeColor: Color {
        if dragOffset.width > 30 { return AppTheme.Colors.success }
        if dragOffset.width < -30 { return AppTheme.Colors.error }
        return .clear
    }
    
    private var swipeBorderColor: Color {
        let opacity = min(Double(abs(dragOffset.width)) / 100.0, 0.8)
        if dragOffset.width > 30 { return AppTheme.Colors.success.opacity(opacity) }
        if dragOffset.width < -30 { return AppTheme.Colors.error.opacity(opacity) }
        return .clear
    }
    
    private var swipeOpacity: Double {
        min(Double(abs(dragOffset.width)) / 100.0, 0.8)
    }
    
    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if value.translation.width > threshold {
                    // Swipe right → Accept
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = CGSize(width: 500, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.approveCurrentItem()
                        dragOffset = .zero
                    }
                } else if value.translation.width < -threshold {
                    // Swipe left → Reject
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = CGSize(width: -500, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.rejectCurrentItem()
                        dragOffset = .zero
                    }
                } else {
                    // Snap back
                    withAnimation(.interactiveSpring()) {
                        dragOffset = .zero
                    }
                }
            }
    }
    
    private func confidenceBadge(_ confidence: ImportConfidence) -> some View {
        let level: ConfidenceBadge.ConfidenceLevel = {
            switch confidence {
            case .high: return .high
            case .medium: return .medium
            case .low: return .low
            }
        }()
        return ConfidenceBadge(level: level, roastMode: roastMode)
    }
    
    private func confidenceColor(_ confidence: ImportConfidence) -> Color {
        switch confidence {
        case .high: return AppTheme.Colors.success
        case .medium: return AppTheme.Colors.primaryAction
        case .low: return AppTheme.Colors.warning
        }
    }
    
    // MARK: - Undo Banner
    
    private var undoBanner: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.undoLastAction()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                Text("Undo")
                    .font(.system(size: 13, weight: .semibold))
                
                if let last = viewModel.lastAction, last.index < viewModel.reviewItems.count {
                    let item = viewModel.reviewItems[last.index]
                    let actionText: String = {
                        switch item.action {
                        case .approved: return "accepted"
                        case .rejected: return "skipped"
                        case .sendToBrainstorm: return "sent to brainstorm"
                        default: return ""
                        }
                    }()
                    if !actionText.isEmpty {
                        Text("— \(actionText)")
                            .font(.system(size: 12))
                            .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                    }
                }
            }
            .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                            .opacity(0.1)
                    )
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: viewModel.canUndo)
        .padding(.bottom, 4)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonRow: some View {
        HStack(spacing: 16) {
            // Reject
            Button {
                withAnimation { viewModel.rejectCurrentItem() }
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.error.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.error)
                    }
                    Text("Skip")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(TouchReactiveStyle(pressedScale: 0.9, hapticStyle: .light))
            
            // Send to Brainstorm
            Button {
                withAnimation { viewModel.sendCurrentToBrainstorm() }
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.brainstormAccent.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.brainstormAccent)
                    }
                    Text("Idea")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(TouchReactiveStyle(pressedScale: 0.9, hapticStyle: .light))
            
            // Edit
            Button {
                showingEditSheet = true
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.primaryAction.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: "pencil")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }
                    Text("Edit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(TouchReactiveStyle(pressedScale: 0.9, hapticStyle: .light))
            
            // Accept — primary action, largest/most prominent
            Button {
                withAnimation { viewModel.approveCurrentItem() }
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.success)
                            .frame(width: 54, height: 54)
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Accept")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.success)
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(TouchReactiveStyle(pressedScale: 0.9, hapticStyle: .medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(roastMode ? AppTheme.Colors.roastSurface : AppTheme.Colors.surfaceElevated)
                .shadow(color: .black.opacity(0.08), radius: 8, y: -3)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Navigation Row
    
    private var navigationRow: some View {
        HStack {
            Button {
                viewModel.goToPrevious()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.subheadline)
            }
            .disabled(!viewModel.hasPrevious)
            
            Spacer()
            
            Button("Save & Finish") {
                Task {
                    await finishAndSave()
                }
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
            
            Spacer()
            
            Button {
                viewModel.goToNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .font(.subheadline)
            }
            .disabled(!viewModel.hasNext)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
    
    // MARK: - States
    
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 30)
                
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppTheme.Colors.warning.opacity(0.15),
                                    AppTheme.Colors.warning.opacity(0.03)
                                ],
                                center: .center, startRadius: 20, endRadius: 60
                            )
                        )
                        .frame(width: 110, height: 110)
                    
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(AppTheme.Colors.warning)
                }
                
                VStack(spacing: 8) {
                    Text("No Jokes Found")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                    
                    Text("GagGrabber couldn't detect any jokes in **\(importResult.sourceFile)**. This can happen for a few reasons.")
                        .font(.system(size: 15))
                        .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                // Why this might happen
                VStack(alignment: .leading, spacing: 14) {
                    Text("Common reasons:")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(roastMode ? .white.opacity(0.9) : AppTheme.Colors.inkBlack)
                    
                    importTipRow(icon: "text.alignleft", text: "The file has very little text or the text is too short for joke detection")
                    importTipRow(icon: "photo", text: "Scanned images have low contrast or blurry text that OCR couldn't read")
                    importTipRow(icon: "textformat", text: "Jokes aren't separated by line breaks or paragraphs")
                    importTipRow(icon: "doc.questionmark", text: "The file format isn't ideal for extraction")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(roastMode ? Color.white.opacity(0.06) : AppTheme.Colors.paperDeep)
                )
                
                // What to try
                VStack(alignment: .leading, spacing: 14) {
                    Text("Try these tips:")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(roastMode ? .white.opacity(0.9) : AppTheme.Colors.inkBlack)
                    
                    importTipRow(icon: "doc.text", text: "Use a **PDF with selectable text** — these work best")
                    importTipRow(icon: "sun.max", text: "For photos: good lighting, flat page, dark ink on white paper")
                    importTipRow(icon: "return", text: "Put each joke on its own line or paragraph")
                    importTipRow(icon: "character.cursor.ibeam", text: "Typed or printed text extracts much better than handwriting")
                    importTipRow(icon: "doc.on.doc", text: "Try splitting large files into smaller chunks")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(roastMode ? Color.white.opacity(0.06) : AppTheme.Colors.paperDeep)
                )
                
                // Supported formats
                VStack(spacing: 8) {
                    Text("Supported formats")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                    
                    HStack(spacing: 8) {
                        formatBadge("PDF")
                        formatBadge("TXT")
                        formatBadge("JPG")
                        formatBadge("PNG")
                        formatBadge("HEIC")
                        formatBadge("DOC")
                    }
                }
                
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14))
                        Text("Try a Different File")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                    )
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.95, hapticStyle: .medium))
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func importTipRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent.opacity(0.8) : AppTheme.Colors.primaryAction)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func formatBadge(_ format: String) -> some View {
        Text(format)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                            .opacity(0.1)
                    )
            )
    }
    
    private var allReviewedState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)
                
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.success.opacity(0.15))
                        .frame(width: 110, height: 110)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(AppTheme.Colors.success)
                }
                
                VStack(spacing: 8) {
                    Text("All Reviewed!")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                    
                    Text("Here's what's ready to save:")
                        .font(.system(size: 15))
                        .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                }
                
                // Summary stats card
                VStack(spacing: 12) {
                    // Source info
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14))
                            .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                        Text(importResult.sourceFile)
                            .font(.system(size: 13))
                            .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text("via \(importResult.providerUsed)")
                            .font(.system(size: 11))
                            .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                    }
                    
                    Divider()
                        .opacity(0.3)
                    
                    // Breakdown
                    let results = viewModel.getReviewResults()
                    
                    summaryStatRow(
                        icon: "checkmark.circle.fill",
                        color: AppTheme.Colors.success,
                        label: "Accepted",
                        count: results.approvedJokes.count
                    )
                    
                    if results.rejectedJokes.count > 0 {
                        summaryStatRow(
                            icon: "xmark.circle.fill",
                            color: AppTheme.Colors.error.opacity(0.7),
                            label: "Skipped",
                            count: results.rejectedJokes.count
                        )
                    }
                    
                    if results.brainstormItems.count > 0 {
                        summaryStatRow(
                            icon: "lightbulb.fill",
                            color: AppTheme.Colors.brainstormAccent,
                            label: "Sent to Brainstorm",
                            count: results.brainstormItems.count
                        )
                    }
                    
                    if viewModel.autoAcceptedCount > 0 {
                        Divider()
                            .opacity(0.3)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.success)
                            Text("\(viewModel.autoAcceptedCount) auto-accepted (high confidence)")
                                .font(.system(size: 12))
                                .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(roastMode ? Color.white.opacity(0.06) : AppTheme.Colors.paperDeep)
                )
                .padding(.horizontal, 16)
                
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task {
                        await finishAndSave()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text("Save \(viewModel.reviewItems.filter { $0.action == .approved }.count) Joke\(viewModel.reviewItems.filter { $0.action == .approved }.count == 1 ? "" : "s")")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                            .fill(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                    )
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.95, hapticStyle: .medium))
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func summaryStatRow(icon: String, color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(roastMode ? .white.opacity(0.8) : AppTheme.Colors.textPrimary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
        }
    }
    
    // MARK: - Swipe Tutorial Overlay
    
    private var swipeTutorialOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissTutorial()
                }
            
            VStack(spacing: 28) {
                Text("How to Review")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                
                // Swipe instructions
                HStack(spacing: 40) {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.error.opacity(0.2))
                                .frame(width: 60, height: 60)
                            Image(systemName: "hand.point.left.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppTheme.Colors.error)
                        }
                        Text("Swipe Left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Skip this joke")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.success.opacity(0.2))
                                .frame(width: 60, height: 60)
                            Image(systemName: "hand.point.right.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppTheme.Colors.success)
                        }
                        Text("Swipe Right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Accept this joke")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                // Button instructions
                VStack(spacing: 8) {
                    Text("Or use the buttons:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    
                    HStack(spacing: 16) {
                        tutorialButtonHint(icon: "xmark", label: "Skip", color: AppTheme.Colors.error)
                        tutorialButtonHint(icon: "lightbulb.fill", label: "Idea", color: AppTheme.Colors.brainstormAccent)
                        tutorialButtonHint(icon: "pencil", label: "Edit", color: AppTheme.Colors.primaryAction)
                        tutorialButtonHint(icon: "checkmark", label: "Keep", color: AppTheme.Colors.success)
                    }
                }
                
                Button {
                    dismissTutorial()
                } label: {
                    Text("Got It!")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                        )
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.95, hapticStyle: .medium))
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: showSwipeTutorial)
    }
    
    private func tutorialButtonHint(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private func dismissTutorial() {
        withAnimation {
            showSwipeTutorial = false
            hasSeenSwipeTutorial = true
        }
    }
    
    // MARK: - Edit Sheet
    
    private func editSheet(for item: ImportReviewItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Title field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                        
                        TextField("Joke title (optional)", text: Binding(
                            get: { viewModel.currentItem?.editedTitle ?? "" },
                            set: { newTitle in
                                viewModel.updateCurrentItemText(
                                    title: newTitle,
                                    body: viewModel.currentItem?.editedBody ?? "",
                                    tags: viewModel.currentItem?.editedTags ?? []
                                )
                            }
                        ))
                        .font(.system(size: 16, weight: .medium))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(roastMode ? Color.white.opacity(0.06) : Color(UIColor.secondarySystemBackground))
                        )
                    }
                    
                    // Body field — TextEditor for multi-line editing
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Content")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                        
                        TextEditor(text: Binding(
                            get: { viewModel.currentItem?.editedBody ?? "" },
                            set: { newBody in
                                viewModel.updateCurrentItemText(
                                    title: viewModel.currentItem?.editedTitle ?? "",
                                    body: newBody,
                                    tags: viewModel.currentItem?.editedTags ?? []
                                )
                            }
                        ))
                        .font(.system(size: 15, design: .serif))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 160)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(roastMode ? Color.white.opacity(0.06) : Color(UIColor.secondarySystemBackground))
                        )
                    }
                    
                    // Tags
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                        
                        if let tags = viewModel.currentItem?.editedTags, !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text(tag)
                                                .font(.system(size: 13))
                                            Button {
                                                var updated = viewModel.currentItem?.editedTags ?? []
                                                updated.removeAll { $0 == tag }
                                                viewModel.updateCurrentItemText(
                                                    title: viewModel.currentItem?.editedTitle ?? "",
                                                    body: viewModel.currentItem?.editedBody ?? "",
                                                    tags: updated
                                                )
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(
                                                roastMode ? AppTheme.Colors.roastAccent.opacity(0.2) : AppTheme.Colors.brand.opacity(0.1)
                                            )
                                        )
                                        .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
                                    }
                                }
                            }
                        } else {
                            Text("No tags — GagGrabber will add them automatically")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    
                    // Original source text
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12))
                            Text("Original Source Text")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                        
                        Text(item.originalJoke.rawSourceText)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(roastMode ? Color.white.opacity(0.03) : Color(UIColor.tertiarySystemBackground))
                            )
                    }
                }
                .padding(20)
            }
            .background(roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
            .navigationTitle("Edit Joke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingEditSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Save Logic
    
    /// Maximum number of save retry attempts
    private let maxSaveRetries = 3
    
    private func finishAndSave() async {
        let results = viewModel.getReviewResults()
        
        // Build the objects to insert but track them so we can roll back on failure.
        var insertedJokes: [Joke] = []
        var insertedIdeas: [BrainstormIdea] = []

        // Insert approved jokes
        for importedJoke in results.approvedJokes {
            let joke = Joke(content: importedJoke.body, title: importedJoke.title ?? "")
            joke.dateCreated = importedJoke.sourceMetadata.importTimestamp
            joke.dateModified = Date()
            joke.tags = importedJoke.tags
            joke.folder = selectedFolder
            joke.importSource = importedJoke.sourceMetadata.fileName
            joke.importConfidence = importedJoke.confidence.rawValue
            joke.importTimestamp = importedJoke.sourceMetadata.importTimestamp
            modelContext.insert(joke)
            insertedJokes.append(joke)
        }
        
        // Insert brainstorm items
        for item in results.brainstormItems {
            let idea = BrainstormIdea(
                content: item.editedBody,
                colorHex: BrainstormIdea.randomColor(),
                isVoiceNote: false
            )
            modelContext.insert(idea)
            insertedIdeas.append(idea)
        }
        
        // Retry save with exponential backoff
        var lastError: Error?
        for attempt in 1...maxSaveRetries {
            do {
                try modelContext.save()
                
                // Small delay to allow CloudKit activity to transition to DONE state
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                savedCount = results.approvedJokes.count
                brainstormCount = results.brainstormItems.count
                showingSaveConfirmation = true
                
                #if DEBUG
                print("✅ [ImportReview] Successfully saved \(savedCount) joke(s) and \(brainstormCount) brainstorm idea(s) (attempt \(attempt))")
                #endif
                return // success — exit the function
            } catch {
                lastError = error
                let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000 // 1s, 2s, 4s
                #if DEBUG
                print("⚠️ [ImportReview] Save attempt \(attempt)/\(maxSaveRetries) failed: \(error.localizedDescription) — retrying in \(Int(pow(2.0, Double(attempt - 1))))s")
                #endif
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        
        // All retries exhausted — roll back all inserted objects to avoid phantom context entries,
        // then surface the error to the user.
        for joke in insertedJokes { modelContext.delete(joke) }
        for idea in insertedIdeas { modelContext.delete(idea) }
        try? modelContext.save() // best-effort rollback flush
        
        // All retries exhausted — show error to user
        let errorDetail = lastError?.localizedDescription ?? "Unknown error"
        saveErrorMessage = "Could not save imported jokes after \(maxSaveRetries) attempts: \(errorDetail)"
        showingSaveError = true
        
        #if DEBUG
        print("❌ [ImportReview] Failed to save after \(maxSaveRetries) attempts: \(errorDetail)")
        if let nsError = lastError as NSError? {
            print("   Domain: \(nsError.domain), Code: \(nsError.code)")
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("   Underlying: \(underlyingError.localizedDescription)")
            }
        }
        #endif
    }
}

// MARK: - Preview

#Preview {
    SmartImportReviewView(
        importResult: ImportPipelineResult(
            sourceFile: "test.txt",
            autoSavedJokes: [],
            reviewQueueJokes: [],
            rejectedBlocks: [],
            pipelineStats: PipelineStats(
                totalPagesProcessed: 1, totalLinesExtracted: 10,
                totalBlocksCreated: 3, autoSavedCount: 2,
                reviewQueueCount: 1, rejectedCount: 0,
                extractionMethod: .documentText,
                processingTimeSeconds: 0.5, averageConfidence: 0.7
            ),
            debugInfo: nil,
            providerUsed: "Extraction"
        )
    )
}
