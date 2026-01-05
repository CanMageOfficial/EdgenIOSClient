# EdgenAI iOS Sample Project

A complete iOS sample application demonstrating how to integrate and use the EdgenAI Client SDK for downloading, managing, and running Core ML models on-device.

## Overview

This sample project showcases:
- 📥 **Model Download Management** - Download Core ML models with progress tracking and resume capability
- 🧠 **Core ML Integration** - Automatic model compilation and execution
- 📸 **Image Processing** - Process images using downloaded models with camera and photo library support
- 💾 **Persistent Storage** - Local model caching and metadata management
- ✨ **Modern SwiftUI** - Built entirely with SwiftUI and Swift Concurrency

## Features

### Model Management
- ✅ Check if models exist locally
- ⬇️ Download models with detailed progress tracking
- ⏸️ Pause and resume downloads
- 🗑️ Cancel and cleanup incomplete downloads
- 🔄 Automatic Core ML model compilation
- 📊 Download statistics (speed, ETA, chunks)

### Image Processing
- 📷 Capture photos with camera
- 🖼️ Select photos from photo library
- 🎨 Process images using Core ML models
- 👀 Side-by-side comparison of original and processed images
- 💾 Save processed images to Photos

### Resumable Downloads
- 🔄 Automatic download resume on app restart
- 📦 Chunk-based downloading with validation
- 🔐 SHA-256 hash verification for integrity
- 💪 Fault-tolerant with automatic retries

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+
- EdgenIOSClient SDK

## Installation

### 1. Add EdgenIOSClient SDK

Add the EdgenIOSClient package to your project:

```swift
dependencies: [
    .package(url: "https://github.com/edgen-ai/edgen-ios-client", from: "1.0.0")
]
```

Or via Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Select your version requirements

### 2. Configure API Credentials

Open `EdgenSwiftUISampleApp.swift` and update the `AppDelegate` with your EdgenAI credentials:

```swift
EdgenAIClient.initialize(
    accessKey: "your_access_key_here",
    secretKey: "your_secret_key_here"
)
```

**Important:** For production apps, store credentials securely:
- Use Keychain Services for sensitive data
- Store in `.xcconfig` files (excluded from source control)
- Use remote configuration services
- Never commit credentials to source control

## Usage

### Basic Model Download

```swift
import SwiftUI
import EdgenIOSClient

struct ContentView: View {
    @State private var modelURL: URL?
    private let modelId = "your_model_id_here"
    private let client = EdgenAIClient()
    
    var body: some View {
        VStack {
            if let url = modelURL {
                Text("Model ready at: \(url.path)")
            } else {
                ModelDownloadView(modelId: modelId) { url in
                    self.modelURL = url
                }
            }
        }
        .onAppear {
            // Check if model already exists
            let result = client.checkModelExists(modelId: modelId)
            if result.exists, let url = result.modelURL {
                self.modelURL = url
            }
        }
    }
}
```

### Download with Progress Tracking

```swift
let client = EdgenAIClient()

Task {
    do {
        let (modelURL, metadataURL) = try await client.downloadModel(
            modelId: "model_id_here"
        ) { progress in
            print("Phase: \(progress.phase)")
            print("Progress: \(progress.percentage)%")
            print("Speed: \(progress.bytesPerSecond) bytes/s")
            print("ETA: \(Int(progress.estimatedTimeRemaining))s")
            print("Chunk: \(progress.currentChunk)/\(progress.totalChunks)")
        }
        
        print("Downloaded to: \(modelURL.path)")
    } catch {
        print("Download failed: \(error.localizedDescription)")
    }
}
```

### Check Download Progress

```swift
let client = EdgenAIClient()

if let progress = client.getDownloadProgress(modelId: "model_id_here") {
    print("Progress: \(Int(progress.progress * 100))%")
    print("Validated chunks: \(progress.validatedChunks.count)/\(progress.totalChunks)")
}
```

### Cancel Download

```swift
let client = EdgenAIClient()
client.cancelDownload(modelId: "model_id_here")
```

### Process Images with Core ML

```swift
let fileConfig = FilePathModelConfiguration(
    modelPath: modelURL,
    inputSize: CGSize(width: 256, height: 256),
    inputName: "x_1",
    outputName: "activation_out"
)

let processedImage = try ModelProcessor.processImage(
    inputImage,
    configuration: fileConfig
)
```

## Download Phases

The download process includes several phases:

1. **Initializing** - Requesting download URLs from server
2. **Downloading** - Downloading model chunks with progress
3. **Merging** - Combining chunks into final file
4. **Validating** - Verifying file integrity with SHA-256
5. **Compiling** - Compiling `.mlmodel` to `.mlmodelc` (if needed)
6. **Complete** - Model ready for use

## Model Configuration

When processing images, configure your model parameters:

```swift
FilePathModelConfiguration(
    modelPath: modelURL,           // Path to .mlmodelc
    inputSize: CGSize(width: 256, height: 256),  // Model input size
    inputName: "x_1",             // Input layer name
    outputName: "activation_out"   // Output layer name
)
```

**Note:** Update these values to match your specific model's requirements.

## Performance Considerations

### Adaptive Concurrency
Downloads automatically adjust concurrent chunk downloads based on network conditions:
- 3 concurrent downloads normally
- 2 concurrent downloads if 10% failure rate
- 1 concurrent download if 30%+ failure rate

### Disk Space Management
- Requires 2x model size for safety (chunks + merged file)
- Automatically validates available disk space
- Cleans up chunks after successful merge

### Hash Verification
- SHA-256 validation for each chunk
- Final file hash verification
- Automatic retry on corruption

Look for log messages like:
- ✅ EdgenAI Client initialized successfully
- 📥 Download plan: X chunks to download
- ⬇️ Downloading chunk X/Y...
- ✅ Model compiled successfully
- ✅ Download completed successfully!

## Troubleshooting

### Download Fails to Start
- Verify API credentials are set in `AppDelegate`
- Check network connectivity
- Ensure sufficient disk space

### Model Compilation Fails
- Verify downloaded file integrity
- Check iOS version compatibility
- Ensure model is valid `.mlmodel` format

### Image Processing Fails
- Verify model input/output names
- Check input image dimensions match model
- Ensure model is compiled (`.mlmodelc`)

### Resume Not Working
- Check if progress state file exists
- Verify chunk files haven't been deleted
- Ensure model metadata hasn't changed

## Best Practices

1. **Always Initialize Early** - Call `EdgenAIClient.initialize()` in `AppDelegate`
2. **Check Before Downloading** - Use `checkModelExists()` to avoid redundant downloads
3. **Handle Cancellation** - Use `withTaskCancellationHandler` for proper cleanup
4. **Validate Credentials** - Never hardcode credentials in production
5. **Monitor Disk Space** - Ensure adequate space before large downloads
6. **Update UI on Main Thread** - Progress callbacks may be on background threads

## License

This sample project is provided as-is for demonstration purposes.

## Support

For issues, questions, or feature requests:
- GitHub Issues: [edgen-ai/edgen-ios-client](https://github.com/edgen-ai/edgen-ios-client)

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues.

---

Built with ❤️ using SwiftUI and EdgenAI
