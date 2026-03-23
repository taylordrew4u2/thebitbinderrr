//
//  BrainstormView.swift
//  thebitbinder
//
//  Brainstorm tab for quick joke thoughts with zoomable grid
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct BrainstormView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BrainstormIdea> { !$0.isDeleted }, sort: \BrainstormIdea.dateCreated, order: .reverse) private var ideas: [BrainstormIdea]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var showAddSheet = false
    @State private var gridScale: CGFloat = 1.0
    @State private var isRecording = false
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var showingPermissionAlert = false
    @State private var selectedIdea: BrainstormIdea?
    @State private var showEditSheet = false
    
    // Batch select/delete mode
    @State private var isSelectMode = false
    @State private var selectedIdeaIDs: Set<UUID> = []
    
    // Grid columns based on scale
    private var columns: [GridItem] {
        let count = max(2, Int(4 / gridScale))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Zoom control slider
                    zoomControl
                    
                    if ideas.isEmpty {
                        emptyState
                    } else {
                        ideaGrid
                    }
                }
            }
            .navigationTitle(roastMode ? "🔥 Fire Ideas" : "Brainstorm")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !ideas.isEmpty {
                        Button {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedIdeaIDs.removeAll() }
                        } label: {
                            Text(isSelectMode ? "Cancel" : "Select")
                                .font(.subheadline)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: BrainstormTrashView()) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundStyle(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.inkBlue)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Button {
                            toggleRecording()
                        } label: {
                            ZStack {
                                // Pulsing ring — only while recording
                                if isRecording {
                                    Circle()
                                        .stroke(AppTheme.Colors.recordingsAccent.opacity(0.4), lineWidth: 3)
                                        .frame(width: 66, height: 66)
                                        .scaleEffect(isRecording ? 1.2 : 1.0)
                                        .opacity(isRecording ? 0 : 1)
                                        .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isRecording)
                                }

                                Circle()
                                    .fill(isRecording
                                        ? LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : (roastMode ? AppTheme.Colors.roastEmberGradient : LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    )
                                    .frame(width: 56, height: 56)

                                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: (isRecording ? AppTheme.Colors.recordingsAccent : (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)).opacity(0.35), radius: 10, y: 5)
                        }
                        .buttonStyle(FABButtonStyle())

                        Button {
                            showAddSheet = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(roastMode ? AppTheme.Colors.roastEmberGradient : AppTheme.Colors.brandGradient)
                                    .frame(width: 56, height: 56)

                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand).opacity(0.35), radius: 10, y: 5)
                        }
                        .buttonStyle(FABButtonStyle())
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
            .sheet(isPresented: $showAddSheet) {
                AddBrainstormIdeaSheet(isVoiceNote: false, initialText: "")
            }
            .sheet(isPresented: $showEditSheet) {
                if let idea = selectedIdea {
                    EditBrainstormIdeaSheet(idea: idea)
                }
            }
            .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
                Button("Settings", role: .none) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable microphone access in Settings to use voice recording.")
            }
        }
        .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.inkBlue)
        .onChange(of: speechManager.isRecording) { oldValue, newValue in
            if oldValue && !newValue && isRecording {
                isRecording = false
            }
        }
    }
    
    // MARK: - Zoom Control
    private var zoomControl: some View {
        HStack(spacing: 16) {
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
            
            Slider(value: $gridScale, in: 0.5...2.0, step: 0.1)
                .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.inkBlue)
            
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        BrainstormEmptyState(
            roastMode: roastMode,
            onAddIdea: { showAddSheet = true }
        )
    }
    
    // MARK: - Idea Grid
    private var ideaGrid: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ideas) { idea in
                        if isSelectMode {
                            ideaSelectableCard(idea: idea)
                        } else {
                            Button {
                                selectedIdea = idea
                                showEditSheet = true
                            } label: {
                                IdeaCard(idea: idea, scale: gridScale, roastMode: roastMode)
                            }
                            .cardPress()
                            .contextMenu {
                                Button {
                                    promoteToJoke(idea)
                                } label: {
                                    Label("Promote to Joke", systemImage: "arrow.up.doc.fill")
                                }
                                
                                Button {
                                    selectedIdea = idea
                                    showEditSheet = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    withAnimation {
                                        idea.moveToTrash()
                                        try? modelContext.save()
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .animation(.easeOut(duration: 0.2), value: gridScale)
            }
            
            // Batch action bar
            if isSelectMode {
                brainstormBatchActionBar
            }
        }
    }
    
    // MARK: - Batch Select Views
    
    @ViewBuilder
    private func ideaSelectableCard(idea: BrainstormIdea) -> some View {
        let isSelected = selectedIdeaIDs.contains(idea.id)
        Button {
            toggleIdeaSelection(idea)
        } label: {
            ZStack(alignment: .topTrailing) {
                IdeaCard(idea: idea, scale: gridScale, roastMode: roastMode)
                    .opacity(isSelected ? 0.7 : 1.0)
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var brainstormBatchActionBar: some View {
        HStack(spacing: 16) {
            Button {
                selectedIdeaIDs = Set(ideas.map(\.id))
            } label: {
                Text("Select All")
                    .font(.subheadline)
            }
            
            Spacer()
            
            Text("\(selectedIdeaIDs.count) selected")
                .font(.subheadline.bold())
                .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
            
            Spacer()
            
            Button(role: .destructive) {
                batchDeleteSelectedIdeas()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.bold())
            }
            .disabled(selectedIdeaIDs.isEmpty)
            .tint(AppTheme.Colors.error)
            
            Button {
                isSelectMode = false
                selectedIdeaIDs.removeAll()
            } label: {
                Text("Done")
                    .font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            (roastMode ? AppTheme.Colors.roastSurface : AppTheme.Colors.surfaceElevated)
                .shadow(.drop(radius: 4, y: -2))
        )
    }
    
    private func toggleIdeaSelection(_ idea: BrainstormIdea) {
        if selectedIdeaIDs.contains(idea.id) {
            selectedIdeaIDs.remove(idea.id)
        } else {
            selectedIdeaIDs.insert(idea.id)
        }
    }
    
    private func batchDeleteSelectedIdeas() {
        withAnimation {
            for idea in ideas where selectedIdeaIDs.contains(idea.id) {
                idea.moveToTrash()
            }
            selectedIdeaIDs.removeAll()
            isSelectMode = false
            do {
                try modelContext.save()
            } catch {
                print("❌ [BrainstormView] Failed to save after batch soft-delete: \(error)")
            }
        }
    }
    
    // MARK: - Speech Recognition
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            requestPermissionAndStartRecording()
        }
    }
    
    private func requestPermissionAndStartRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    if #available(iOS 17.0, *) {
                        AVAudioApplication.requestRecordPermission { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    self.startRecording()
                                } else {
                                    self.showingPermissionAlert = true
                                }
                            }
                        }
                    } else {
                        AVAudioSession.sharedInstance().requestRecordPermission { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    self.startRecording()
                                } else {
                                    self.showingPermissionAlert = true
                                }
                            }
                        }
                    }
                default:
                    self.showingPermissionAlert = true
                }
            }
        }
    }
    
    private func startRecording() {
        speechManager.startRecording()
        isRecording = true
    }
    
    private func stopRecording() {
        speechManager.stopRecording()
        
        // Save the transcribed text as a new idea
        let text = speechManager.transcribedText
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let newIdea = BrainstormIdea(
                content: text,
                colorHex: BrainstormIdea.randomColor(),
                isVoiceNote: true
            )
            modelContext.insert(newIdea)
            try? modelContext.save()
            speechManager.transcribedText = ""
        }
        
        // Reset recording state with animation so pulsing ring is cleanly removed
        withAnimation(.easeOut(duration: 0.2)) {
            isRecording = false
        }
    }
    
    // MARK: - Promote to Joke
    
    private func promoteToJoke(_ idea: BrainstormIdea) {
        // Create a new joke from the brainstorm idea
        let title = String(idea.content.prefix(60))
        let joke = Joke(content: idea.content, title: title, folder: nil)
        joke.importSource = "Brainstorm"
        
        modelContext.insert(joke)
        
        // Save joke first — only soft-delete the idea once it's confirmed persisted
        do {
            try modelContext.save()
        } catch {
            // Save failed — remove the unsaved joke to avoid a phantom entry
            modelContext.delete(joke)
            print("❌ [BrainstormView] Failed to save promoted joke: \(error)")
            return
        }
        
        // Only soft-delete the idea after the joke is confirmed saved
        withAnimation {
            idea.moveToTrash()
        }
        
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [BrainstormView] Joke saved but failed to trash original idea: \(error)")
        }
        
        // Notify user with haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Speech Recognition Manager

class SpeechRecognitionManager: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    @Published var transcribedText = ""
    @Published var isRecording = false
    
    func startRecording() {
        // Reset any previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        transcribedText = ""
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("Audio session setup failed: \(error)")
            #endif
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            #if DEBUG
            print("Unable to create recognition request")
            #endif
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                DispatchQueue.main.async {
                    self.isRecording = false
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            #if DEBUG
            print("Audio engine start failed: \(error)")
            #endif
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    deinit {
        recognitionTask?.cancel()
        audioEngine.stop()
    }
}

// MARK: - Idea Card

struct IdeaCard: View {
    let idea: BrainstormIdea
    let scale: CGFloat
    let roastMode: Bool
    
    // Refined 5-color palette (less rainbow, more cohesive)
    private static let refinedColors: [String: Color] = [
        "FFF9C4": Color(red: 1.0, green: 0.97, blue: 0.77),      // Soft yellow
        "FFECB3": Color(red: 1.0, green: 0.92, blue: 0.70),      // Warm amber
        "E3F2FD": Color(red: 0.89, green: 0.95, blue: 0.99),     // Light blue
        "F3E5F5": Color(red: 0.95, green: 0.90, blue: 0.96),     // Soft lavender
        "E8F5E9": Color(red: 0.91, green: 0.96, blue: 0.91),     // Mint green
    ]
    
    private var cardColor: Color {
        // Map old colors to refined palette, or use default
        if let color = Self.refinedColors[idea.colorHex] {
            return color
        }
        // Default to warm cream
        return Color(red: 0.99, green: 0.96, blue: 0.90)
    }
    
    private var cardHeight: CGFloat {
        max(90, 130 * scale)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with voice indicator
            HStack(spacing: 6) {
                if idea.isVoiceNote {
                    HStack(spacing: 3) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: max(9, 10 * scale), weight: .medium))
                        Text("Voice")
                            .font(.system(size: max(8, 9 * scale), weight: .medium))
                    }
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent.opacity(0.7) : AppTheme.Colors.primaryAction.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(roastMode ? AppTheme.Colors.roastAccent.opacity(0.15) : AppTheme.Colors.primaryAction.opacity(0.1))
                    )
                }
                Spacer()
            }
            
            // Content
            Text(idea.content)
                .font(.system(size: max(11, 13 * scale), weight: .regular, design: .serif))
                .foregroundColor(roastMode ? .white.opacity(0.92) : AppTheme.Colors.inkBlack.opacity(0.9))
                .lineLimit(Int(max(3, 6 * scale)))
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 4)
            
            // Footer with timestamp
            HStack {
                Spacer()
                Text(idea.dateCreated.formatted(.dateTime.month(.abbreviated).day().hour(.defaultDigits(amPM: .abbreviated)).minute()))
                    .font(.system(size: max(8, 9 * scale)))
                    .foregroundColor(roastMode ? .white.opacity(0.35) : AppTheme.Colors.textTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .fill(roastMode ? AppTheme.Colors.roastCard : cardColor)
                .shadow(color: roastMode ? .black.opacity(0.25) : .black.opacity(0.06), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .strokeBorder(
                    roastMode
                        ? AppTheme.Colors.roastAccent.opacity(0.2)
                        : Color.black.opacity(0.04),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Brainstorm Empty State

struct BrainstormEmptyState: View {
    var roastMode: Bool = false
    var onAddIdea: (() -> Void)? = nil
    
    var body: some View {
        BitBinderEmptyState(
            icon: roastMode ? "flame.fill" : "lightbulb.fill",
            title: roastMode ? "No Fire Ideas Yet" : "No Ideas Yet",
            subtitle: "Tap + to write or use the mic to capture thoughts by voice",
            actionTitle: "Add Idea",
            action: onAddIdea,
            roastMode: roastMode,
            iconGradient: roastMode
                ? AppTheme.Colors.roastEmberGradient
                : LinearGradient(
                    colors: [AppTheme.Colors.brainstormAccent, AppTheme.Colors.brainstormAccent.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
        )
    }
}

#Preview {
    BrainstormView()
        .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
