//
//  DocumentScannerView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import VisionKit

#if !targetEnvironment(macCatalyst)
struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: ([UIImage]) -> Void
        
        init(completion: @escaping ([UIImage]) -> Void) {
            self.completion = completion
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }
            completion(images)
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            #if DEBUG
            print("Document scanner failed: \(error)")
            #endif
            controller.dismiss(animated: true)
        }
    }
}
#else
/// Stub so call sites compile on macOS Catalyst (camera scanning not available)
struct DocumentScannerView: View {
    let completion: ([UIImage]) -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Document scanning is not available on Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}
#endif
