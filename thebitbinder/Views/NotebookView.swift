import SwiftUI
import PhotosUI
import SwiftData
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Folder Filter

/// Which subset of photos to display.
private enum NotebookFilter: Equatable, Hashable {
    case all
    case unfiled
    case folder(UUID)
}

struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<NotebookPhotoRecord> { !$0.isDeleted }, sort: \NotebookPhotoRecord.sortOrder) private var allPhotos: [NotebookPhotoRecord]
    @Query(filter: #Predicate<NotebookFolder> { !$0.isDeleted }, sort: \NotebookFolder.sortOrder) private var folders: [NotebookFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var showingDetail: NotebookPhotoRecord?
    @State private var showingImagePicker = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var showingTrash = false
    @State private var persistenceError: String?
    @State private var showingPersistenceError = false
    @State private var showingPDFPicker = false
    @State private var isImportingPDF = false
    @State private var pdfImportProgress: String = ""
    @State private var draggingPhoto: NotebookPhotoRecord?

    // Folder state
    @State private var selectedFilter: NotebookFilter = .all
    @State private var showingCreateFolder = false
    @State private var showingMoveSheet = false
    @State private var photoToMove: NotebookPhotoRecord?
    @State private var showingRenameFolder = false
    @State private var folderToRename: NotebookFolder?
    @State private var showingDeleteFolderAlert = false
    @State private var folderToDelete: NotebookFolder?

    /// Photos that match the current filter.
    private var filteredPhotos: [NotebookPhotoRecord] {
        switch selectedFilter {
        case .all:
            return allPhotos
        case .unfiled:
            return allPhotos.filter { $0.folder == nil }
        case .folder(let id):
            return allPhotos.filter { $0.folder?.id == id }
        }
    }

    /// The currently-selected folder object (if any).
    private var selectedFolder: NotebookFolder? {
        guard case .folder(let id) = selectedFilter else { return nil }
        return folders.first { $0.id == id }
    }
    
    private func delete(_ photo: NotebookPhotoRecord) {
        // Soft-delete: imageData kept until permanently purged from NotebookTrashView
        photo.moveToTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookView] Failed to save after photo soft-delete: \(error)")
            persistenceError = "Could not delete photo: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }
    
    private func move(from source: NotebookPhotoRecord, to destination: NotebookPhotoRecord) {
        guard source.id != destination.id else { return }
        
        var orderedPhotos = filteredPhotos
        guard let sourceIndex = orderedPhotos.firstIndex(where: { $0.id == source.id }),
              let destIndex = orderedPhotos.firstIndex(where: { $0.id == destination.id }) else { return }
        
        // Move the item
        let movedItem = orderedPhotos.remove(at: sourceIndex)
        orderedPhotos.insert(movedItem, at: destIndex)
        
        // Update sort orders
        for (index, photo) in orderedPhotos.enumerated() {
            photo.sortOrder = index
        }
        
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookView] Failed to save reorder: \(error)")
        }
    }
    
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Folder Filter Bar
            if !folders.isEmpty {
                folderBar
            }

            // MARK: - Photo Grid
            Group {
                if filteredPhotos.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredPhotos, id: \.id) { photo in
                                NotebookThumbnailCell(photo: photo, isDragging: draggingPhoto?.id == photo.id) {
                                    showingDetail = photo
                                } onDelete: {
                                    delete(photo)
                                } onMove: {
                                    photoToMove = photo
                                    showingMoveSheet = true
                                }
                                .onDrag {
                                    draggingPhoto = photo
                                    return NSItemProvider(object: photo.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: NotebookDropDelegate(
                                    item: photo,
                                    draggingItem: $draggingPhoto,
                                    onMove: move
                                ))
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .overlay {
            if isImportingPDF {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text(pdfImportProgress)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingCamera = true } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    PhotosPicker(selection: $pickedPhotoItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    Button { showingPDFPicker = true } label: {
                        Label("Import PDF", systemImage: "doc.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingCreateFolder = true } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }

                    if let folder = selectedFolder {
                        Button { folderToRename = folder; showingRenameFolder = true } label: {
                            Label("Rename Folder", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            folderToDelete = folder
                            showingDeleteFolderAlert = true
                        } label: {
                            Label("Delete Folder", systemImage: "folder.badge.minus")
                        }
                    }

                    Divider()

                    Button { showingTrash = true } label: {
                        Label("Trash", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingTrash) {
            NotebookTrashView()
        }
        .onChange(of: pickedPhotoItem) { oldValue, newValue in
                Task {
                    if let item = newValue {
                        await importPhoto(from: item)
                        pickedPhotoItem = nil
                    }
                }
            }
        .sheet(isPresented: $showingCamera, onDismiss: {
            if let cameraImage {
                Task {
                    await saveCameraImage(cameraImage)
                }
                self.cameraImage = nil
            }
        }) {
            CameraView(image: $cameraImage)
        }
        .sheet(item: $showingDetail) { photo in
            NotebookDetailView(photo: photo)
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $showingPDFPicker) {
            NotebookPDFPickerView { urls in
                if let url = urls.first {
                    Task {
                        await importPDF(from: url)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateFolder) {
            CreateNotebookFolderSheet()
        }
        .sheet(isPresented: $showingRenameFolder) {
            if let folder = folderToRename {
                RenameNotebookFolderSheet(folder: folder)
            }
        }
        .sheet(isPresented: $showingMoveSheet) {
            if let photo = photoToMove {
                MoveToNotebookFolderSheet(photo: photo)
            }
        }
        .alert("Delete Folder?", isPresented: $showingDeleteFolderAlert) {
            Button("Cancel", role: .cancel) { folderToDelete = nil }
            Button("Delete", role: .destructive) {
                if let folder = folderToDelete {
                    deleteFolder(folder)
                    folderToDelete = nil
                }
            }
        } message: {
            Text("The folder will be deleted but your photos will be kept as unfiled pages.")
        }
        .onDisappear {
            // Memory cleanup handled by MemoryManager
        }
        .alert("Error", isPresented: $showingPersistenceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }

    // MARK: - Folder Bar

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                folderChip(label: "All", icon: "photo.on.rectangle.angled", isSelected: selectedFilter == .all) {
                    selectedFilter = .all
                }

                // "Unfiled" chip
                let unfiledCount = allPhotos.filter { $0.folder == nil }.count
                folderChip(label: "Unfiled", icon: "tray", count: unfiledCount, isSelected: selectedFilter == .unfiled) {
                    selectedFilter = .unfiled
                }

                // Each folder
                ForEach(folders) { folder in
                    folderChip(
                        label: folder.name,
                        icon: "folder.fill",
                        count: folder.activePhotoCount,
                        isSelected: selectedFilter == .folder(folder.id)
                    ) {
                        selectedFilter = .folder(folder.id)
                    }
                    .contextMenu {
                        Button { folderToRename = folder; showingRenameFolder = true } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            folderToDelete = folder
                            showingDeleteFolderAlert = true
                        } label: {
                            Label("Delete Folder", systemImage: "folder.badge.minus")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func folderChip(label: String, icon: String, count: Int? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected
                          ? (Color.blue)
                          : Color(UIColor.secondarySystemGroupedBackground))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        switch selectedFilter {
        case .all:
            BitBinderEmptyState(
                icon: "book.fill",
                title: roastMode ? "No Notebook Pages" : "No Pages Saved Yet",
                subtitle: "Take photos of your physical notebook pages or import PDFs to back them up",
                roastMode: roastMode
            )
        case .unfiled:
            BitBinderEmptyState(
                icon: "tray",
                title: "No Unfiled Pages",
                subtitle: "All your pages are organized into folders",
                roastMode: roastMode
            )
        case .folder:
            BitBinderEmptyState(
                icon: "folder",
                title: "Empty Folder",
                subtitle: "Move pages here from All or another folder",
                roastMode: roastMode
            )
        }
    }

    // MARK: - Folder Actions

    private func deleteFolder(_ folder: NotebookFolder) {
        // Nullify rule handles un-assigning photos automatically.
        // Move the folder itself to trash (soft-delete).
        folder.moveToTrash()
        // Reset filter if this folder was selected
        if case .folder(let id) = selectedFilter, id == folder.id {
            selectedFilter = .all
        }
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookView] Failed to delete folder: \(error)")
            persistenceError = "Could not delete folder: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }

    // MARK: - Import Helpers
    
    private func importPhoto(from item: PhotosPickerItem) async {
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self) else { return }

            // Downscale to max 1500 px long edge then compress.
            guard let jpegData: Data = autoreleasepool(invoking: {
                guard let uiImage = UIImage(data: rawData) else { return nil }
                let scaled = NotebookView.downscaleForStorage(uiImage, maxLongEdge: 1500)
                return scaled.jpegData(compressionQuality: 0.8)
            }) else { return }

            let newPhoto = NotebookPhotoRecord(notes: "", imageData: jpegData)
            // Assign to current folder if viewing one
            if let folder = selectedFolder {
                newPhoto.folder = folder
            }
            await MainActor.run {
                modelContext.insert(newPhoto)
                do {
                    try modelContext.save()
                } catch {
                    print(" [NotebookView] Failed to save imported photo: \(error)")
                    persistenceError = "Could not save photo: \(error.localizedDescription)"
                    showingPersistenceError = true
                }
            }
        } catch {
            print(" [NotebookView] importPhoto error: \(error)")
        }
    }
    
    private func saveCameraImage(_ image: UIImage) async {
        guard let jpegData: Data = autoreleasepool(invoking: {
            let scaled = NotebookView.downscaleForStorage(image, maxLongEdge: 1500)
            return scaled.jpegData(compressionQuality: 0.8)
        }) else { return }

        let newPhoto = NotebookPhotoRecord(notes: "", imageData: jpegData)
        if let folder = selectedFolder {
            newPhoto.folder = folder
        }
        await MainActor.run {
            modelContext.insert(newPhoto)
            do {
                try modelContext.save()
            } catch {
                print(" [NotebookView] Failed to save camera photo: \(error)")
                persistenceError = "Could not save photo: \(error.localizedDescription)"
                showingPersistenceError = true
            }
        }
    }

    /// Scales `image` so its longest edge is at most `maxLongEdge` pixels.
    static func downscaleForStorage(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - PDF Import
    
    private func importPDF(from url: URL) async {
        await MainActor.run {
            isImportingPDF = true
            pdfImportProgress = "Loading PDF..."
        }
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        
        guard let document = PDFDocument(url: url) else {
            await MainActor.run {
                isImportingPDF = false
                persistenceError = "Could not open PDF file"
                showingPersistenceError = true
            }
            return
        }
        
        let pageCount = document.pageCount
        let pdfName = url.deletingPathExtension().lastPathComponent
        let targetFolder = selectedFolder // capture for async
        
        for pageIndex in 0..<pageCount {
            await MainActor.run {
                pdfImportProgress = "Importing page \(pageIndex + 1) of \(pageCount)..."
            }
            
            guard let page = document.page(at: pageIndex) else { continue }
            guard let jpegData = await renderPDFPageToJPEG(page: page) else { continue }
            
            let notes = pageCount > 1 
                ? "\(pdfName) (Page \(pageIndex + 1) of \(pageCount))"
                : pdfName
            
            let newPhoto = NotebookPhotoRecord(notes: notes, imageData: jpegData)
            if let folder = targetFolder {
                newPhoto.folder = folder
            }
            
            await MainActor.run {
                modelContext.insert(newPhoto)
            }
        }
        
        await MainActor.run {
            pdfImportProgress = "Saving..."
            do {
                try modelContext.save()
            } catch {
                print(" [NotebookView] Failed to save PDF pages: \(error)")
                persistenceError = "Could not save PDF pages: \(error.localizedDescription)"
                showingPersistenceError = true
            }
            isImportingPDF = false
        }
    }
    
    private func renderPDFPageToJPEG(page: PDFPage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                let mediaBox = page.bounds(for: .mediaBox)
                guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }
                
                let maxDimension: CGFloat = 1500
                let scale = min(maxDimension / mediaBox.width, maxDimension / mediaBox.height, 2.0)
                let scaledSize = CGSize(
                    width: (mediaBox.width * scale).rounded(),
                    height: (mediaBox.height * scale).rounded()
                )
                
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                
                let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
                let image = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: scaledSize))
                    
                    let cg = ctx.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: scaledSize.height)
                    cg.scaleBy(x: scale, y: -scale)
                    cg.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)
                    page.draw(with: .mediaBox, to: cg)
                    cg.restoreGState()
                }
                
                return image.jpegData(compressionQuality: 0.85)
            }
        }.value
    }
}

// MARK: - PDF Picker for Notebook

struct NotebookPDFPickerView: UIViewControllerRepresentable {
    let completion: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        
        init(completion: @escaping ([URL]) -> Void) {
            self.completion = completion
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion([])
        }
    }
}

struct NotebookDetailView: View {
    @Bindable var photo: NotebookPhotoRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<NotebookPhotoRecord> { !$0.isDeleted }, sort: \NotebookPhotoRecord.sortOrder) private var allPhotos: [NotebookPhotoRecord]
    
    @State private var currentIndex: Int = 0
    @State private var showingNotes = false
    
    private func deleteCurrent() {
        guard currentIndex < allPhotos.count else { return }
        let photoToDelete = allPhotos[currentIndex]
        photoToDelete.moveToTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookDetailView] Failed to save after photo soft-delete: \(error)")
        }
        
        // If we deleted the last photo, dismiss
        if allPhotos.count <= 1 {
            dismiss()
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                if allPhotos.isEmpty {
                    Text("No photos")
                        .foregroundColor(.secondary)
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(allPhotos.enumerated()), id: \.element.id) { index, photo in
                            ZoomableImageView(photo: photo)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        deleteCurrent()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    if !allPhotos.isEmpty {
                        Text("\(currentIndex + 1) of \(allPhotos.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showingNotes = true
                        } label: {
                            Image(systemName: "note.text")
                        }
                        
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNotes) {
                if currentIndex < allPhotos.count {
                    NotebookNotesSheet(photo: allPhotos[currentIndex])
                }
            }
            .onAppear {
                // Find the index of the initially selected photo
                if let index = allPhotos.firstIndex(where: { $0.id == photo.id }) {
                    currentIndex = index
                }
            }
        }
    }
}

// MARK: - Notes Sheet

struct NotebookNotesSheet: View {
    @Bindable var photo: NotebookPhotoRecord
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Notes") {
                    TextEditor(text: $photo.notes)
                        .frame(minHeight: 150)
                }
                
                Section {
                    LabeledContent("Added") {
                        Text(photo.dateCreated, style: .date)
                    }
                }
            }
            .navigationTitle("Page Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let photo: NotebookPhotoRecord
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var body: some View {
        GeometryReader { geometry in
            if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newScale = lastScale * value
                                scale = min(max(newScale, minScale), maxScale)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= minScale {
                                    withAnimation(.spring(response: 0.3)) {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > minScale {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                withAnimation(.spring(response: 0.3)) {
                                    if scale > minScale {
                                        scale = minScale
                                        offset = .zero
                                        lastScale = minScale
                                        lastOffset = .zero
                                    } else {
                                        scale = 2.5
                                        lastScale = 2.5
                                    }
                                }
                            }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Color(UIColor.secondarySystemBackground)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Image not available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .onChange(of: photo.id) { _, _ in
            // Reset zoom when switching photos
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
}

// MARK: - CameraView (UIKit wrapped)

#if !targetEnvironment(macCatalyst)
struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView
        init(parent: CameraView) { self.parent = parent }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage { parent.image = uiImage }
            parent.dismiss()
        }
    }
}
#else
struct CameraView: View {
    @Binding var image: UIImage?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Camera is not available on Mac.\nUse the photo picker instead.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}
#endif

// MARK: - Notebook Thumbnail Cell
//
// Decodes the stored JPEG into a fixed 200×200 px thumbnail on a background
// thread, so the main thread and LazyVGrid are never blocked by image decode,
// and only ~120 KB per cell is held in memory (vs 3–8 MB for a full UIImage).

private struct NotebookThumbnailCell: View {
    let photo: NotebookPhotoRecord
    var isDragging: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void
    let onMove: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
                    .overlay(ProgressView().tint(.secondary))
            }
        }
        .frame(minWidth: 100, minHeight: 100)
        .clipped()
        .cornerRadius(8)
        .opacity(isDragging ? 0.5 : 1.0)
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .onTapGesture { onTap() }
        .contextMenu {
            Button(action: onMove) {
                Label("Move to Folder", systemImage: "folder")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .task(id: photo.id) {
            await decodeThumbnail()
        }
    }

    private func decodeThumbnail() async {
        guard thumbnail == nil, let data = photo.imageData else { return }
        // Hop off the main actor — image decode is CPU-bound
        let decoded: UIImage? = await Task.detached(priority: .utility) {
            autoreleasepool {
                guard let full = UIImage(data: data) else { return nil }
                // Render at 200 px max long edge (sufficient for a grid thumbnail)
                let size = full.size
                let longEdge = max(size.width, size.height)
                guard longEdge > 200 else { return full }
                let scale = 200.0 / longEdge
                let newSize = CGSize(width: (size.width * scale).rounded(),
                                    height: (size.height * scale).rounded())
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = 1
                fmt.opaque = true
                return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
                    full.draw(in: CGRect(origin: .zero, size: newSize))
                }
            }
        }.value
        thumbnail = decoded
    }
}

// MARK: - Create Notebook Folder Sheet

struct CreateNotebookFolderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var folderName = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Name") {
                    TextField("Enter folder name", text: $folderName)
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createFolder() }
                        .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .tint(.blue)
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func createFolder() {
        let folder = NotebookFolder(name: folderName.trimmingCharacters(in: .whitespaces))
        modelContext.insert(folder)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(" [CreateNotebookFolder] Failed to save: \(error)")
            saveErrorMessage = "Could not create folder: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}

// MARK: - Rename Notebook Folder Sheet

struct RenameNotebookFolderSheet: View {
    @Bindable var folder: NotebookFolder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Name") {
                    TextField("Folder name", text: $newName)
                }
            }
            .navigationTitle("Rename Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { renameFolder() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { newName = folder.name }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func renameFolder() {
        folder.name = newName.trimmingCharacters(in: .whitespaces)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(" [RenameNotebookFolder] Failed to save: \(error)")
            saveErrorMessage = "Could not rename folder: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}

// MARK: - Move to Notebook Folder Sheet

struct MoveToNotebookFolderSheet: View {
    @Bindable var photo: NotebookPhotoRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<NotebookFolder> { !$0.isDeleted }, sort: \NotebookFolder.name) private var folders: [NotebookFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            List {
                // "Unfiled" option
                Button {
                    movePhoto(to: nil)
                } label: {
                    HStack {
                        Label("Unfiled", systemImage: "tray")
                        Spacer()
                        if photo.folder == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .tint(.primary)

                // Folder options
                ForEach(folders) { folder in
                    Button {
                        movePhoto(to: folder)
                    } label: {
                        HStack {
                            Label(folder.name, systemImage: "folder.fill")
                            Spacer()
                            if photo.folder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .tint(.blue)
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func movePhoto(to folder: NotebookFolder?) {
        photo.folder = folder
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(" [MoveToFolder] Failed to save: \(error)")
            saveErrorMessage = "Could not move photo: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}

// MARK: - Drop Delegate for Reordering

private struct NotebookDropDelegate: DropDelegate {
    let item: NotebookPhotoRecord
    @Binding var draggingItem: NotebookPhotoRecord?
    let onMove: (NotebookPhotoRecord, NotebookPhotoRecord) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let dragging = draggingItem, dragging.id != item.id else { return }
        onMove(dragging, item)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}