# EdgenIOSClient

A Swift package for downloading and managing Large Language Models (LLMs) and Core ML models on iOS, iPadOS, and tvOS devices from the EdgenAI platform.

[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015%20|%20tvOS%2015-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

| Feature | Description |
|---------|-------------|
| 📥 **Model Downloads** | Chunked downloads with automatic retry and resume |
| 📊 **Progress Tracking** | Real-time download statistics and phase updates |
| ✅ **Validation** | SHA-256 hash verification for data integrity |
| 🔄 **Auto Compilation** | Automatic Core ML model compilation |
| 📱 **Model Management** | Built-in UI for browsing and managing models |
| 🖼️ **Image Processing** | Ready-to-use Core ML image processing utilities |
| 👁️ **Image Comparison** | Before/after comparison views |
| 📷 **Camera Integration** | Camera and photo library access |
| 💾 **Disk Management** | Automatic space verification |
| ⚡ **Concurrent Downloads** | Adaptive multi-chunk downloading |

## Table of Contents

- [Features](#features)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Quick Start with Sample App](#quick-start-with-sample-app)
  - [Installation](#installation)
- [Quick Usage Guide](#quick-usage-guide)
- [Key Capabilities](#key-capabilities)
- [Core ML Model Configuration](#core-ml-model-configuration)
- [Platform Support](#platform-support)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)


## Getting Started

### Prerequisites

1. **Create an Account**: Visit [https://edgenai.canmage.com](https://edgenai.canmage.com)
2. **Upload or Select Models**: Upload your own models or browse publicly available ones
3. **Generate API Keys**: Create a download key to receive your **Access Key** and **Secret Key**
4. **Get Model IDs**: Note the Model IDs of the models you want to download

### Quick Start with Sample App

The fastest way to get started:

1. **Clone and open the project**:
   ```bash
   git clone https://github.com/CanMageOfficial/EdgenIOSClient.git
   ```

2. **Configure credentials** in `EdgenSwiftUISampleApp.swift`:
   ```swift
   EdgenAIClient.initialize(
       accessKey: "your_access_key_here",
       secretKey: "your_secret_key_here"
   )
   ```

3. **Update model ID** in the app:
   ```swift
   ModelDownloadView(modelId: "your_model_id_here")
   ```

4. **Add privacy descriptions** to `Info.plist` (for camera/photo access):
   ```xml
   <key>NSCameraUsageDescription</key>
   <string>This app needs camera access to process images with AI models</string>
   <key>NSPhotoLibraryUsageDescription</key>
   <string>This app needs photo library access to select images</string>
   <key>NSPhotoLibraryAddUsageDescription</key>
   <string>This app needs permission to save processed images</string>
   ```

5. **Build and run** (⌘R)

The sample app demonstrates the complete workflow: downloading models, processing images, and managing downloads.

### Installation

Add EdgenIOSClient to your project using Swift Package Manager:

#### Via Xcode

1. **File → Add Package Dependencies...**
2. Enter: `https://github.com/CanMageOfficial/EdgenIOSClient`
3. Select version and click **Add Package**

#### Via Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/CanMageOfficial/EdgenIOSClient", from: "1.0.0")
]
```

## Quick Usage Guide

### Initialize the SDK

```swift
import EdgenIOSClient

@main
struct YourApp: App {
    init() {
        EdgenAIClient.initialize(
            accessKey: "your_access_key",
            secretKey: "your_secret_key"
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

> ⚠️ **Security Note**: Never hardcode credentials in production. Use Keychain or environment variables.

### Download a Model

```swift
let client = EdgenAIClient()

do {
    try await client.downloadModel(modelId: "your_model_id") { progress in
        print("Progress: \(progress.percentage)%")
    }
    print("Download complete!")
} catch {
    print("Download failed: \(error)")
}
```

### Check if Model Exists

```swift
let result = client.checkModelExistence(modelId: "your_model_id")
if result.exists {
    print("Model ready at: \(result.modelURL?.path ?? "unknown")")
}
```

### Use Built-in Model Management UI

```swift
import SwiftUI
import EdgenIOSClient

struct ContentView: View {
    var body: some View {
        NavigationView {
            DownloadedModelsView()
        }
    }
}
```

### Process Images with Core ML

The sample app automatically extracts model configuration. For manual configuration:

```swift
let config = FilePathModelConfiguration(
    modelPath: modelURL,
    inputSize: CGSize(width: 256, height: 256),
    inputName: "input",
    outputName: "output"
)

let processedImage = try ModelProcessor.processImage(inputImage, configuration: config)
```

**For detailed code examples**, see the included **EdgenSwiftUISample** app.

## Key Capabilities

### Resume Capability
Downloads automatically resume from where they left off. Progress is saved after each chunk, and hash validation ensures integrity.

### Adaptive Concurrency
The download system adjusts concurrent chunk downloads based on network conditions (up to 3 concurrent), reducing concurrency on failures and auto-retrying up to 3 times.

### Disk Space Management
Automatic disk space verification before downloads with clear error messages if space is insufficient.

### Core ML Integration
Core ML models (`.mlmodel`) are automatically compiled to `.mlmodelc` format for optimized on-device inference.

### Security
- Bearer token authentication
- SHA-256 hash verification for all chunks
- HTTPS for all network requests

## Core ML Model Configuration

### Model Configuration Structure

```swift
public struct FilePathModelConfiguration {
    public let modelPath: URL          // Path to .mlmodelc file
    public let inputSize: CGSize       // Input dimensions (e.g., 256x256)
    public let inputName: String       // Input layer name
    public let outputName: String      // Output layer name
}
```

### Finding Input/Output Names

**Using Xcode**: Open `.mlmodel` file → View "Inputs" and "Outputs" sections

**Programmatically**: The sample app includes automatic model configuration extraction. See `ProcessImageView.extractModelConfiguration()` for implementation details.

### Model Metadata

Each downloaded model includes metadata:

```swift
public struct ModelMetadata: Codable {
    public let modelName: String      // Human-readable name
    public let modelId: String         // Unique identifier
    public let version: String         // Model version
    public let description: String     // Description
    public let category: String        // Category
    public let hash: String            // SHA-256 hash
    public let downloadDate: Date      // Download timestamp
}
```

### Progress Information

```swift
public struct DetailedProgress {
    public var percentage: Double              // 0-100
    public var downloadedBytes: Int64          // Downloaded so far
    public var totalBytes: Int64               // Total size
    public var bytesPerSecond: Double          // Download speed
    public var estimatedTimeRemaining: TimeInterval // ETA
    public var currentChunk: Int               // Current chunk
    public var totalChunks: Int                // Total chunks
    public var phase: DownloadPhase            // Current phase
}

public enum DownloadPhase {
    case initializing, downloading, merging, validating, compiling, complete
}
```

## Platform Support

- **iOS**: 15.0+
- **tvOS**: 15.0+
- **Swift**: 6.2+

> **Note**: macOS support is planned for a future release.

## Troubleshooting

### Download Issues
- **Fails immediately**: Check credentials, model ID, network, and permissions
- **Slow download**: Network speed is the primary factor; SDK auto-adjusts concurrency

### Core ML Issues
- **Compilation fails**: Verify `.mlmodel` format and device compatibility
- **Processing fails**: Check input/output names match model, correct input size, using `.mlmodelc` format
- **Memory issues**: Large models may fail on older devices

### Camera/Photos Access
Add required privacy descriptions to `Info.plist`:
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`  
- `NSPhotoLibraryAddUsageDescription`

### Storage Issues
Use `DownloadedModelsView` to manage and delete unused models.

## API Reference

### EdgenAIClient

```swift
// Initialize SDK
static func initialize(accessKey: String, secretKey: String)

// Download model
func downloadModel(
    modelId: String,
    onProgress: ((DetailedProgress) -> Void)?
) async throws

// Check if model exists
func checkModelExistence(modelId: String) -> ModelExistenceResult

// Cancel downloads
func cancelDownload(modelId: String)
func cancelAllDownloads()
```

### UI Components

```swift
// Model management view
struct DownloadedModelsView: View

// Image comparison view
struct EnhancedImageComparisonView: View {
    let originalImage: UIImage
    let processedImage: UIImage?
}

// Image picker
struct ImagePickerWithVideo: UIViewControllerRepresentable
```

### Utilities

```swift
// Process images with Core ML
class ModelProcessor {
    static func processImage(
        _ image: UIImage,
        configuration: FilePathModelConfiguration
    ) throws -> UIImage
}

// Save to photo library
class AlbumUtils {
    static func saveImage(image: UIImage?)
}
```

**For detailed examples and complete implementation**, see the **EdgenSwiftUISample** app included in this repository.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Documentation**: [https://edgenai.canmage.com/docs](https://edgenai.canmage.com/docs)
- **Issues**: [GitHub Issues](https://github.com/CanMageOfficial/EdgenIOSClient/issues)
- **Email**: support@canmage.com

## Acknowledgments

Built with ❤️ using Swift and SwiftUI for the EdgenAI platform.

---

© 2026 EdgenAI. All rights reserved.
