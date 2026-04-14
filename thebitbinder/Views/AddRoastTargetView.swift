//
//  AddRoastTargetView.swift
//  thebitbinder
//
//  Sheet to create a new person to roast.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddRoastTargetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""
    @State private var traits: [String] = [""]
    @State private var openingRoastCount: Int = 3
    @State private var showingGuidedCreation = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
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

                Section("Who are you roasting?") {
                    TextField("Name", text: $name)
                        .font(.headline)
                }

                Section("Notes (optional)") {
                    TextField("e.g. friend, coworker, celebrity...", text: $notes)
                }
                
                Section {
                    Picker("Main Roasts", selection: $openingRoastCount) {
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
                    ForEach(Array(traits.enumerated()), id: \.offset) { index, _ in
                        if index < traits.count {
                            HStack {
                                TextField("e.g. works in finance, always late...", text: Binding(
                                    get: { index < traits.count ? traits[index] : "" },
                                    set: { newValue in
                                        if index < traits.count {
                                            traits[index] = newValue
                                        }
                                    }
                                ))
                                if traits.count > 1 {
                                    Button {
                                        if index < traits.count {
                                            traits.remove(at: index)
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
                        traits.append("")
                    } label: {
                        Label("Add another", systemImage: "plus.circle")
                            .foregroundColor(accentColor)
                    }
                } header: {
                    Text("What do you know about them?")
                } footer: {
                    Text("Bullet points about the target — habits, quirks, job, looks, anything roastable.")
                }

                Section {
                    Button {
                        showingGuidedCreation = true
                    } label: {
                        HStack {
                            Text("")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Let BitBuddy Guide You")
                                    .font(.headline)
                                    .foregroundColor(accentColor)
                                Text("Answer questions to build the profile")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(UIColor.systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(accentColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        saveTarget()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task(id: selectedPhoto) {
                await loadSelectedPhoto()
            }
            .onAppear {
                #if DEBUG
                print(" [AddRoastTargetView] View appeared")
                print(" [AddRoastTargetView] ModelContext available: \(modelContext)")
                #endif
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .sheet(isPresented: $showingGuidedCreation) {
                GuidedRoastTargetSheet { guidedName, guidedNotes, guidedTraits in
                    name = guidedName
                    notes = guidedNotes
                    traits = guidedTraits.isEmpty ? [""] : guidedTraits
                }
            }
        }
    }

    private func saveTarget() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let cleanTraits = traits
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let target = RoastTarget(
            name: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            traits: cleanTraits,
            photoData: photoData
        )
        target.openingRoastCount = openingRoastCount
        
        modelContext.insert(target)
        
        do {
            try modelContext.save()
            #if DEBUG
            print(" [AddRoastTargetView] Target '\(trimmed)' saved successfully (id: \(target.id))")
            #endif
            dismiss()
        } catch {
            #if DEBUG
            print(" [AddRoastTargetView] Failed to save: \(error)")
            #endif
            saveErrorMessage = "Could not save target: \(error.localizedDescription)"
            showSaveError = true
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
            guard photoData != scaledData else {
                self.selectedPhoto = nil
                return
            }
            photoData = scaledData
            photoImage = scaled
            self.selectedPhoto = nil
        }
    }
}

// MARK: - BitBuddy Guided Roast Target Creation

struct GuidedRoastTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var onComplete: (String, String, [String]) -> Void
    
    @State private var step = 1
    @State private var name = ""
    @State private var notes = ""
    @State private var traits: [String] = []
    @State private var currentTrait = ""
    @State private var promptIndex = 0
    @State private var displayedPrompt = ""
    
    private let accentColor: Color = .blue
    
    private let traitPrompts = [
        "What's their job or what do they do?",
        "Any annoying habits or quirks?",
        "What do they look like? Any standout features?",
        "What are they known for in your friend group?",
        "Anything else that could be roast material?"
    ]
    
    private var currentPromptText: String {
        switch step {
        case 1: return "Who are you roasting? Give me a name."
        case 2: return "How do you know them? Friend, coworker, family?"
        case 3:
            if promptIndex < traitPrompts.count {
                return traitPrompts[promptIndex]
            }
            return "Anything else? Or tap Done to finish."
        case 4: return "Here's your target profile. Look good?"
        default: return ""
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor.opacity(0.2))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentColor)
                                .frame(width: geo.size.width * CGFloat(step) / 4, height: 4)
                                .animation(.easeOut, value: step)
                        }
                }
                .frame(height: 4)
                .padding(.horizontal)
                .padding(.top, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // BitBuddy prompt
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color(UIColor.tertiarySystemBackground))
                                    .frame(width: 36, height: 36)
                                Text("")
                                    .font(.system(size: 18))
                            }
                            
                            Text(displayedPrompt)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(16)
                                .cornerRadius(4, corners: [.topRight, .bottomLeft, .bottomRight])
                        }
                        .padding(.top, 16)
                        
                        // Input area based on step
                        switch step {
                        case 1:
                            guidedTextField("Name", text: $name, placeholder: "Their name...")
                            nextButton(disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
                                step = 2
                            }
                            
                        case 2:
                            guidedTextField("Relationship", text: $notes, placeholder: "e.g. coworker, best friend, ex...")
                            nextButton(disabled: false) {
                                step = 3
                            }
                            
                        case 3:
                            guidedTextField("", text: $currentTrait, placeholder: "Type something about them...")
                            
                            HStack(spacing: 12) {
                                Button {
                                    let trimmed = currentTrait.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty {
                                        traits.append(trimmed)
                                        currentTrait = ""
                                    }
                                    if promptIndex < traitPrompts.count - 1 {
                                        promptIndex += 1
                                        animatePrompt()
                                    }
                                } label: {
                                    Text("Add & Next")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(accentColor)
                                        .cornerRadius(12)
                                }
                                
                                Button {
                                    let trimmed = currentTrait.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty {
                                        traits.append(trimmed)
                                    }
                                    step = 4
                                } label: {
                                    Text("Done")
                                        .font(.headline)
                                        .foregroundColor(accentColor)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(accentColor.opacity(0.15))
                                        .cornerRadius(12)
                                }
                            }
                            
                            if !traits.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Added so far:")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.5))
                                    ForEach(traits, id: \.self) { trait in
                                        HStack(spacing: 6) {
                                            Text("•")
                                                .foregroundColor(accentColor)
                                            Text(trait)
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                            
                        case 4:
                            // Review
                            VStack(alignment: .leading, spacing: 12) {
                                reviewRow("Name", value: name)
                                if !notes.isEmpty {
                                    reviewRow("Relationship", value: notes)
                                }
                                if !traits.isEmpty {
                                    Text("Intel")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.5))
                                    ForEach(traits, id: \.self) { trait in
                                        HStack(spacing: 6) {
                                            Text("•")
                                                .foregroundColor(accentColor)
                                            Text(trait)
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(12)
                            
                            Button {
                                onComplete(name, notes, traits)
                                dismiss()
                            } label: {
                                Text("Create Target")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(accentColor)
                                    .cornerRadius(12)
                            }
                            
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(UIColor.systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(accentColor)
                }
            }
        }
        .onAppear {
            animatePrompt()
        }
        .onChange(of: step) {
            animatePrompt()
        }
    }
    
    private func guidedTextField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            TextField(placeholder, text: text)
                .font(.body)
                .padding(14)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(12)
                .foregroundColor(.primary)
        }
    }
    
    private func nextButton(disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Next")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(disabled ? accentColor.opacity(0.3) : accentColor)
                .cornerRadius(12)
        }
        .disabled(disabled)
    }
    
    private func reviewRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    private func animatePrompt() {
        displayedPrompt = ""
        let fullText = currentPromptText
        let words = fullText.split(separator: " ")
        Task {
            for (index, word) in words.enumerated() {
                try? await Task.sleep(nanoseconds: 40_000_000)
                await MainActor.run {
                    if index == 0 {
                        displayedPrompt = String(word)
                    } else {
                        displayedPrompt += " " + String(word)
                    }
                }
            }
        }
    }
}
