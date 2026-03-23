//
//  NotebookTrashView.swift
//  thebitbinder
//
//  Trash bin for soft-deleted notebook photos.
//  Restore puts the photo back in the active grid.
//  "Delete Forever" permanently removes the imageData from the store.
//

import SwiftUI
import SwiftData

struct NotebookTrashView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("roastModeEnabled") private var roastMode = false
    @Query(
        filter: #Predicate<NotebookPhotoRecord> { $0.isDeleted == true },
        sort: \NotebookPhotoRecord.deletedDate,
        order: .reverse
    ) private var trashedPhotos: [NotebookPhotoRecord]

    @State private var showingEmptyTrashAlert = false

    var body: some View {
        Group {
            if trashedPhotos.isEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Photo Trash is Empty",
                    subtitle: "Deleted notebook photos appear here for 30 days before being permanently removed.",
                    roastMode: roastMode
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(trashedPhotos, id: \.id) { photo in
                            ZStack(alignment: .bottomTrailing) {
                                Group {
                                    if let data = photo.imageData, let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Color.gray.overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.white)
                                        )
                                    }
                                }
                                .frame(minWidth: 100, minHeight: 100)
                                .clipped()
                                .cornerRadius(8)
                                .opacity(0.65) // Visual cue that item is in trash
                            }
                            .contextMenu {
                                Button {
                                    photo.restoreFromTrash()
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("❌ [NotebookTrashView] Failed to restore photo: \(error)")
                                    }
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }

                                Button(role: .destructive) {
                                    modelContext.delete(photo)
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("❌ [NotebookTrashView] Failed to permanently delete photo: \(error)")
                                    }
                                } label: {
                                    Label("Delete Forever", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Photo Trash")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !trashedPhotos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingEmptyTrashAlert = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                }
            }
        }
        .alert("Empty Photo Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                for photo in trashedPhotos {
                    modelContext.delete(photo)
                }
                do {
                    try modelContext.save()
                } catch {
                    print("❌ [NotebookTrashView] Failed to save after empty trash: \(error)")
                }
            }
        } message: {
            Text("This permanently deletes all \(trashedPhotos.count) photo\(trashedPhotos.count == 1 ? "" : "s") and their image data. This cannot be undone.")
        }
    }
}

#Preview {
    NavigationStack {
        NotebookTrashView()
    }
    .modelContainer(for: NotebookPhotoRecord.self, inMemory: true)
}
