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
    @AppStorage("showFullContent") private var showFullContent = true
    @AppStorage("brainstormGridScale") private var brainstormGridScale: Double = 1.0
    
    @State private var showAddSheet = false
    @GestureState private var pinchMagnification: CGFloat = 1.0
    @State private var isRecording = false
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var showingPermissionAlert = false
    
    // Batch select/delete mode
    @State private var isSelectMode = false
    @State private var selectedIdeaIDs: Set<UUID> = []
    
    // Persistence error surfacing
    @State private var showingTrash = false
    @State private var showTalkToText = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false
    
    // Pinch-to-zoom
    private var effectiveGridScale: CGFloat {
        min(max(CGFloat(brainstormGridScale) * pinchMagnification, 0.5), 2.0)
    }
    
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                brainstormGridScale = Double(min(max(CGFloat(brainstormGridScale) * value.magnification, 0.5), 2.0))
            }
    }
    
    // Grid columns based on scale
    private var columns: [GridItem] {
        let count = max(2, Int(4 / effectiveGridScale))
        return Array(repeating: GridItem(.flexible(), spacing: 0), count: count)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if ideas.isEmpty {
                emptyState
            } else {
                ideaGrid
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        toggleRecording()
                    } label: {
                        Label(isRecording ? "Stop Recording" : "Voice Note", systemImage: isRecording ? "stop.circle.fill" : "mic.fill")
                    }
                    Button {
                        showTalkToText = true
                    } label: {
                        Label("Talk to Text", systemImage: "mic.badge.plus")
                    }
                    Section {
                        Button(action: { showFullContent.toggle() }) {
                            Label(showFullContent ? "Show Titles Only" : "Show Full Content",
                                  systemImage: showFullContent ? "list.bullet" : "text.justify.leading")
                        }
                        if !ideas.isEmpty {
                            Button {
                                isSelectMode.toggle()
                                if !isSelectMode { selectedIdeaIDs.removeAll() }
                            } label: {
                                Label(isSelectMode ? "Cancel Select" : "Select Multiple",
                                      systemImage: isSelectMode ? "xmark.circle" : "checkmark.circle")
                            }
                        }
                    }
                    Section {
                        Button { showingTrash = true } label: {
                            Label("Trash", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingTrash) {
            BrainstormTrashView()
        }
        .sheet(isPresented: $showAddSheet) {
            AddBrainstormIdeaSheet(isVoiceNote: false, initialText: "")
        }
        .sheet(isPresented: $showTalkToText) {
            TalkToTextView(selectedFolder: nil, saveToBrainstorm: true)
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
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
        .tint(.blue)
        .onChange(of: speechManager.isRecording) { oldValue, newValue in
            if oldValue && !newValue && isRecording {
                isRecording = false
            }
        }
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
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(ideas) { idea in
                        if isSelectMode {
                            ideaSelectableCard(idea: idea)
                        } else {
                            NavigationLink {
                                BrainstormDetailView(idea: idea)
                            } label: {
                                IdeaCard(idea: idea, scale: effectiveGridScale, roastMode: roastMode, showFullContent: showFullContent)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    promoteToJoke(idea)
                                } label: {
                                    Label("Promote to Joke", systemImage: "arrow.up.doc.fill")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    withAnimation {
                                        idea.moveToTrash()
                                        do {
                                            try modelContext.save()
                                        } catch {
                                            print(" [BrainstormView] Failed to save after soft-delete: \(error)")
                                            persistenceError = "Could not delete thought: \(error.localizedDescription)"
                                            showingErrorAlert = true
                                        }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .animation(.easeOut(duration: 0.2), value: effectiveGridScale)
            }
            .simultaneousGesture(pinchGesture)
            
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
                IdeaCard(idea: idea, scale: effectiveGridScale, roastMode: roastMode, showFullContent: showFullContent)
                    .opacity(isSelected ? 0.7 : 1.0)
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
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
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(role: .destructive) {
                batchDeleteSelectedIdeas()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.bold())
            }
            .disabled(selectedIdeaIDs.isEmpty)
            .tint(.red)
            
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
        .background(.bar)
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
                print(" [BrainstormView] Failed to save after batch soft-delete: \(error)")
                persistenceError = "Could not delete thoughts: \(error.localizedDescription)"
                showingErrorAlert = true
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
            do {
                try modelContext.save()
            } catch {
                print(" [BrainstormView] Failed to save voice note idea: \(error)")
                persistenceError = "Could not save voice note: \(error.localizedDescription)"
                showingErrorAlert = true
            }
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
            print(" [BrainstormView] Failed to save promoted joke: \(error)")
            return
        }
        
        // Only soft-delete the idea after the joke is confirmed saved
        withAnimation {
            idea.moveToTrash()
        }
        
        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormView] Joke saved but failed to trash original idea: \(error)")
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

// MARK: - Idea Card (simplified)

struct IdeaCard: View {
    let idea: BrainstormIdea
    let scale: CGFloat
    let roastMode: Bool
    var showFullContent: Bool = true
    
    private var accentColor: Color {
        let hex = idea.colorHex
        if !hex.isEmpty, let parsed = Color(hex: hex) {
            return parsed
        }
        return .blue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thin color accent bar at the top
            accentColor
                .frame(height: 3)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
            
            VStack(alignment: .leading, spacing: 6) {
                // Voice indicator (subtle badge)
                if idea.isVoiceNote {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Voice")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(roastMode ? .blue.opacity(0.7) : .accentColor.opacity(0.6))
                }
                
                // Content
                if showFullContent {
                    Text(idea.content)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineSpacing(2)
                        .lineLimit(6)
                } else {
                    Text(idea.content.components(separatedBy: .newlines).first ?? idea.content)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // Timestamp (minimal)
                Text(idea.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, max(8, 10 * scale))
            .padding(.vertical, max(8, 10 * scale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Brainstorm Empty State

struct BrainstormEmptyState: View {
    var roastMode: Bool = false
    var onAddIdea: (() -> Void)? = nil
    
    var body: some View {
        BitBinderEmptyState(
            icon: roastMode ? "flame.fill" : "lightbulb.fill",
            title: roastMode ? "No Ideas Yet" : "No Ideas Yet",
            subtitle: "Tap + to write or use the mic to capture thoughts by voice",
            actionTitle: "Add Idea",
            action: onAddIdea,
            roastMode: roastMode
        )
    }
}

#Preview {
    BrainstormView()
        .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
