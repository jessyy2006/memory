//
//  ImagePickerView.swift
//  Memory
//
//  Created by Jessica Young on 11/28/25.
//

import SwiftUI
import PhotosUI

struct ImagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let memoryService: MemoryService
    let userId: UUID
    let onComplete: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var capturedImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = selectedImage ?? capturedImage {
                    // Preview
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .cornerRadius(15)
                        .padding()

                    // Save Button
                    Button(action: saveImage) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save Memory")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(15)
                    .padding(.horizontal)
                    .disabled(isProcessing)

                } else {
                    // Selection Options
                    VStack(spacing: 20) {
                        Text("Add a Photo")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top, 40)

                        // Camera Button
                        Button(action: { showCamera = true }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                Text("Take Photo")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(15)
                        }
                        .padding(.horizontal)

                        // Photo Library Picker
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            HStack {
                                Image(systemName: "photo.fill")
                                    .font(.title2)
                                Text("Choose from Library")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(15)
                        }
                        .padding(.horizontal)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(capturedImage: $capturedImage)
            }
            .onChange(of: selectedItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
        }
    }

    private func saveImage() {
        guard let image = selectedImage ?? capturedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to process image"
            return
        }

        isProcessing = true
        Task {
            do {
                try await memoryService.createPhotoMemory(userId: userId, imageData: imageData)
                await MainActor.run {
                    isProcessing = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to save photo: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var capturedImage: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
