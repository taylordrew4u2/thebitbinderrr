//
//  JokesViewModifiers.swift
//  thebitbinder
//
//  Extracted sheet & alert modifiers from JokesView to reduce
//  body complexity and avoid compiler type-check timeouts.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Sheets Modifier

struct JokesSheetsModifier: ViewModifier {
    @Binding var showingAddJoke: Bool
    @Binding var showingScanner: Bool
    @Binding var showingCreateFolder: Bool
    @Binding var showingAutoOrganize: Bool
    @Binding var showingAudioImport: Bool
    @Binding var showingTalkToText: Bool
    @Binding var showingFilePicker: Bool
    @Binding var showingAddRoastTarget: Bool
    @Binding var showingMoveJokesSheet: Bool
    @Binding var showingReviewSheet: Bool

    let selectedFolder: JokeFolder?
    let folders: [JokeFolder]
    @Binding var folderPendingDeletion: JokeFolder?
    let reviewCandidates: [JokeImportCandidate]
    let possibleDuplicates: [String]
    let unresolvedFragments: [UnresolvedImportFragment]
    let processScannedImages: ([UIImage]) -> Void
    let processDocuments: ([URL]) -> Void
    let moveJokes: (JokeFolder, JokeFolder?) -> Void
    let deleteFolder: (JokeFolder) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingAddJoke) {
                AddJokeView(selectedFolder: selectedFolder)
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { images in
                    processScannedImages(images)
                }
            }
            .sheet(isPresented: $showingCreateFolder) {
                CreateFolderView()
            }
            .sheet(isPresented: $showingAutoOrganize) {
                AutoOrganizeView()
            }
            .sheet(isPresented: $showingAudioImport) {
                AudioImportView(selectedFolder: selectedFolder)
            }
            .sheet(isPresented: $showingTalkToText) {
                TalkToTextView(selectedFolder: selectedFolder)
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPickerView { urls in
                    processDocuments(urls)
                }
            }
            .sheet(isPresented: $showingAddRoastTarget) {
                AddRoastTargetView()
                    .onAppear {
                        #if DEBUG
                        print("✅ [JokesViewModifiers] AddRoastTargetView sheet appeared")
                        #endif
                    }
            }
            .sheet(isPresented: $showingMoveJokesSheet) {
                MoveJokesSheet(
                    folders: folders,
                    folderPendingDeletion: $folderPendingDeletion,
                    showingMoveJokesSheet: $showingMoveJokesSheet,
                    moveJokes: moveJokes,
                    deleteFolder: deleteFolder
                )
            }
            .sheet(isPresented: $showingReviewSheet) {
                ReviewImportsSheet(
                    showingReviewSheet: $showingReviewSheet,
                    reviewCandidates: reviewCandidates,
                    possibleDuplicates: possibleDuplicates,
                    unresolvedFragments: unresolvedFragments,
                    selectedFolder: selectedFolder
                )
            }
    }
}

// MARK: - Alerts Modifier

struct JokesAlertsModifier: ViewModifier {
    @Binding var showingExportAlert: Bool
    @Binding var showingImportSummary: Bool
    @Binding var showingDeleteFolderAlert: Bool
    @Binding var showingDeleteRoastAlert: Bool
    @Binding var showingMoveJokesSheet: Bool

    let exportedPDFURL: URL?
    let importSummary: (added: Int, skipped: Int)
    @Binding var folderPendingDeletion: JokeFolder?
    @Binding var roastTargetToDelete: RoastTarget?
    let jokes: [Joke]
    let shareFile: (URL) -> Void
    let removeJokesFromFolderAndDelete: (JokeFolder) -> Void
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .alert("PDF Exported", isPresented: $showingExportAlert) {
                if let url = exportedPDFURL {
                    Button("Share") { shareFile(url) }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your jokes have been exported to a PDF file.")
            }
            .alert("Import Complete", isPresented: $showingImportSummary) {
                Button("OK") {}
            } message: {
                Text("Imported \(importSummary.added) jokes. Skipped \(importSummary.skipped).")
            }
            .alert("Delete Folder?", isPresented: $showingDeleteFolderAlert) {
                Button("Move Jokes…") {
                    showingMoveJokesSheet = true
                }
                Button("Remove From Folder", role: .destructive) {
                    if let folder = folderPendingDeletion {
                        removeJokesFromFolderAndDelete(folder)
                    }
                }
                Button("Cancel", role: .cancel) {
                    folderPendingDeletion = nil
                }
            } message: {
                let count = folderPendingDeletion.map { f in jokes.filter { $0.folder?.id == f.id }.count } ?? 0
                Text("This will delete the folder '\(folderPendingDeletion?.name ?? "")'. You can move its \(count) jokes to another folder, or remove them from any folder.")
            }
            .alert("Delete Roast Target?", isPresented: $showingDeleteRoastAlert) {
                Button("Delete", role: .destructive) {
                    if let target = roastTargetToDelete {
                        modelContext.delete(target)
                        try? modelContext.save()
                        roastTargetToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    roastTargetToDelete = nil
                }
            } message: {
                Text("This will delete \(roastTargetToDelete?.name ?? "") and all their roast jokes permanently.")
            }
    }
}

// MARK: - Move Jokes Sheet (extracted)

struct MoveJokesSheet: View {
    let folders: [JokeFolder]
    @Binding var folderPendingDeletion: JokeFolder?
    @Binding var showingMoveJokesSheet: Bool
    let moveJokes: (JokeFolder, JokeFolder?) -> Void
    let deleteFolder: (JokeFolder) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button(action: {
                    if let folder = folderPendingDeletion {
                        moveJokes(folder, nil)
                        deleteFolder(folder)
                    }
                    showingMoveJokesSheet = false
                    folderPendingDeletion = nil
                }) {
                    Label("Move to No Folder", systemImage: "tray")
                }
                ForEach(folders) { dest in
                    if dest.id != folderPendingDeletion?.id {
                        Button(action: {
                            if let source = folderPendingDeletion {
                                moveJokes(source, dest)
                                deleteFolder(source)
                            }
                            showingMoveJokesSheet = false
                            folderPendingDeletion = nil
                        }) {
                            Label(dest.name, systemImage: "folder")
                        }
                    }
                }
            }
            .navigationTitle("Move Jokes To…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingMoveJokesSheet = false }
                }
            }
        }
    }
}

// NOTE: ImportProgressCard has been moved to JokeComponents.swift

// MARK: - Review Imports Sheet (extracted)

struct ReviewImportsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var showingReviewSheet: Bool
    let reviewCandidates: [JokeImportCandidate]
    let possibleDuplicates: [String]
    let unresolvedFragments: [UnresolvedImportFragment]
    let selectedFolder: JokeFolder?

    var body: some View {
        NavigationStack {
            List {
                if !possibleDuplicates.isEmpty {
                    Section("Possible Duplicates") {
                        ForEach(possibleDuplicates, id: \.self) { dup in
                            Label(dup, systemImage: "exclamationmark.triangle")
                                .foregroundColor(AppTheme.Colors.warning)
                        }
                    }
                }
                if !unresolvedFragments.isEmpty {
                    Section("Unresolved Fragments") {
                        ForEach(unresolvedFragments.filter { !$0.isResolved }) { fragment in
                            UnresolvedFragmentRow(
                                fragment: fragment,
                                selectedFolder: selectedFolder,
                                onSaveAsJoke: { saveFragmentAsJoke($0) },
                                onMarkResolved: { markResolved($0) }
                            )
                        }
                    }
                }
                if !reviewCandidates.isEmpty {
                    Section("Needs Review") {
                        ForEach(Array(reviewCandidates.enumerated()), id: \.element.id) { _, cand in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Title", text: .constant(cand.suggestedTitle))
                                    .textFieldStyle(.roundedBorder)
                                Text(cand.content)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(6)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review Imports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingReviewSheet = false }
                }
            }
        }
    }
    
    private func saveFragmentAsJoke(_ fragment: UnresolvedImportFragment) {
        let title = fragment.titleCandidate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? fragment.titleCandidate!
            : String(fragment.text.prefix(40))
        let joke = Joke(content: fragment.text, title: title, folder: selectedFolder)
        joke.tags = fragment.tags
        modelContext.insert(joke)
        fragment.isResolved = true
        try? modelContext.save()
    }
    
    private func markResolved(_ fragment: UnresolvedImportFragment) {
        fragment.isResolved = true
        try? modelContext.save()
    }
}

struct UnresolvedFragmentRow: View {
    let fragment: UnresolvedImportFragment
    let selectedFolder: JokeFolder?
    let onSaveAsJoke: (UnresolvedImportFragment) -> Void
    let onMarkResolved: (UnresolvedImportFragment) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(fragment.titleCandidate ?? "Recovered Fragment")
                    .font(.headline)
                Spacer()
                Text(fragment.confidence.capitalized)
                    .font(.caption.bold())
                    .foregroundStyle(fragment.confidence == "high" ? .green : fragment.confidence == "medium" ? .orange : .red)
            }
            
            Text(fragment.text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(8)
            
            HStack(spacing: 12) {
                Text(fragment.kind.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)
                Text(fragment.sourceFilename)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let page = fragment.sourcePage {
                    Text("Page \(page)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 10) {
                Button {
                    onSaveAsJoke(fragment)
                } label: {
                    Label("Save as Joke", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button {
                    onMarkResolved(fragment)
                } label: {
                    Label("Mark Resolved", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
