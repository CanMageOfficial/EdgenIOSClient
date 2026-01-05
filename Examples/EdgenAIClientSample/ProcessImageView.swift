import SwiftUI
import CoreML
import Vision
import UIKit
import PhotosUI
import EdgenIOSClient

struct ProcessImageView: View {
    @State private var inputImage: UIImage?
    @State private var outputImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    
    var modelURL: URL
    
    var body: some View {
        ScrollView {
            VStack {
                HStack(spacing: 15) {
                    Button(action: {
                        showingCamera = true
                    }) {
                        CameraButtonLabel()
                    }
                    
                    Button(action: { showingPhotoPicker = true }) {
                        PhotoButtonLabel()
                    }
                }.padding(.top, 8).padding(.bottom)
                
                if let inputImage = inputImage {
                    ZStack {
                        EnhancedImageComparisonView(
                            originalImage: inputImage,
                            processedImage: outputImage,
                        )
                        .frame(maxHeight: 400)
                        
                        if isProcessing {
                            VStack {
                                ProgressView()
                                Text("Processing...")
                            }
                            .padding()
                        }
                    }
                } else {
                    GallerySelectionView(title: "Select a photo")
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                VStack(spacing: 15) {
                    if inputImage != nil {
                        Button(action: processImage) {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                }
                                Text(isProcessing ? "Processing..." : "Process")
                            }
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(inputImage != nil && !isProcessing ? Color.blue : Color.gray.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isProcessing)
                    }
                    
                    if outputImage != nil {
                        Button{
                            AlbumUtils.saveImage(image: outputImage)
                        } label: {
                            SaveToPhotosLabel()
                        }
                    }
                }
            }.navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Image Processor")
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink{
                        DownloadedModelsView()
                    } label: {
                        Image(systemName: "square.grid.3x3.fill")
                            .imageScale(.large)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            ImagePickerWithVideo(
                image: $inputImage,
                sourceType: .camera
            ) { image in
                outputImage = nil
                inputImage = image
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            ImagePickerWithVideo(
                image: $inputImage,
                sourceType: .photoLibrary
            ) { image in
                outputImage = nil
                inputImage = image
            }
        }
    }
    
    private func processImage() {
        guard let inputImage = inputImage else { return }
        
        isProcessing = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Automatically extract model configuration from the Core ML model
                let fileConfig = try ModelProcessor.extractModelConfiguration(from: modelURL)
                let resultImage = try ModelProcessor.processImage(inputImage, configuration: fileConfig)
                
                DispatchQueue.main.async {
                    self.outputImage = resultImage
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Processing failed: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
}
