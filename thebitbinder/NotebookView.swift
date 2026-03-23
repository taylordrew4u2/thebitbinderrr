import SwiftUI
import PhotosUI
import SwiftData
import AVFoundation

extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var photos: [NotebookPhotoRecord]
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var showingDetail: NotebookPhotoRecord?
    @State private var showingImagePicker = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    
    private func delete(_ photo: NotebookPhotoRecord) {
        // Remove from SwiftData (imageData is stored directly, no file to delete)
        modelContext.delete(photo)
        try? modelContext.save()
    }
    
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]
    
    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    BitBinderEmptyState(
                        icon: "book.fill",
                        title: roastMode ? "No Fire Notebook Pages" : "No Pages Saved Yet",
                        subtitle: "Take photos of your physical notebook pages to back them up in the app",
                        roastMode: roastMode,
                        iconGradient: LinearGradient(
                            colors: [AppTheme.Colors.notebookAccent, AppTheme.Colors.notebookAccent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(photos, id: \.id) { photo in
                                // Load image from stored imageData
                                if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(minWidth: 100, minHeight: 100)
                                        .clipped()
                                        .cornerRadius(8)
                                        .onTapGesture { showingDetail = photo }
                                        .contextMenu {
                                            Button(role: .destructive) { delete(photo) } label: { Label("Delete", systemImage: "trash") }
                                        }
                                } else {
                                    Color.gray
                                        .frame(minWidth: 100, minHeight: 100)
                                        .cornerRadius(8)
                                        .overlay(Text("No Image").foregroundColor(.white))
                                        .onTapGesture { showingDetail = photo }
                                        .contextMenu {
                                            Button(role: .destructive) { delete(photo) } label: { Label("Delete", systemImage: "trash") }
                                        }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(roastMode ? "🔥 Fire Notebook" : "Notebook Saver")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $pickedPhotoItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        Label("Add Photo", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                }
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
            .onDisappear {
                // Memory cleanup handled by MemoryManager
            }
        }
    }
    
    private func importPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let uiImage = UIImage(data: data) else { return }
            
            // Compress and store as imageData directly
            if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                let newPhoto = NotebookPhotoRecord(notes: "", imageData: jpegData)
                await MainActor.run {
                    modelContext.insert(newPhoto)
                    try? modelContext.save()
                }
            }
        } catch {
            // ignore errors silently for now
        }
    }
    
    private func saveCameraImage(_ image: UIImage) async {
        // Compress and store as imageData directly
        if let jpegData = image.jpegData(compressionQuality: 0.8) {
            let newPhoto = NotebookPhotoRecord(notes: "", imageData: jpegData)
            await MainActor.run {
                modelContext.insert(newPhoto)
                try? modelContext.save()
            }
        }
    }
    
}

struct NotebookDetailView: View {
    @Bindable var photo: NotebookPhotoRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    private func deleteCurrent() {
        // Delete model and dismiss (imageData stored directly, no file to remove)
        modelContext.delete(photo)
        try? modelContext.save()
        dismiss()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Load image from stored imageData
                if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .padding()
                } else {
                    Color.gray
                        .frame(height: 200)
                        .cornerRadius(12)
                        .overlay(Text("Image not found").foregroundColor(.white))
                        .padding()
                }
                TextField("Notes", text: $photo.notes)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Notebook Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        deleteCurrent()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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
