import SwiftUI
import Combine

public struct ModelDownloadView: View {
    @StateObject private var downloadManager = DownloadManager()
    var modelId: String
    var onDownloadComplete: (URL) -> Void = { _ in }

    public init(modelId: String, onDownloadComplete: @escaping (URL) -> Void = { _ in }) {
        self.modelId = modelId
        self.onDownloadComplete = onDownloadComplete
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            if !downloadManager.modelAlreadyExists && downloadManager.downloadedFile == nil {
                Button(action: {
                    downloadManager.startDownload(modelId: modelId)
                }) {
                    HStack {
                        if downloadManager.isDownloading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text("Downloading...")
                        } else if downloadManager.canResume {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Resume Download")
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Model")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(downloadManager.isDownloading ? Color.gray : (downloadManager.canResume ? Color.orange : Color.blue))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(downloadManager.isDownloading)
                
                // Cancel Download Button (only shown during download or if resume available)
                if downloadManager.isDownloading || downloadManager.canResume {
                    Button(action: {
                        downloadManager.cancelDownload(modelId: modelId)
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Cancel & Cleanup")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            }

            // Download Progress
            if downloadManager.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: downloadManager.detailedProgress.percentage, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    Text("\(Int(downloadManager.detailedProgress.percentage))%")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 8)
            }
            
            // Resume Information
            if downloadManager.resumeInfo != nil {
                VStack(alignment: .leading, spacing: 5) {
                    
                    if !downloadManager.isDownloading {
                        ProgressView(value: downloadManager.detailedProgress.percentage, total: 100)
                            .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                    }
                }
                .padding()
                .cornerRadius(8)
            }
            
            // Model Already Exists
            if downloadManager.modelAlreadyExists {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Model already exists!")
                        .foregroundColor(.green)
                        .font(.headline)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            // Error Message
            if let error = downloadManager.errorMessage {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Downloaded File Info
            if downloadManager.downloadedFile != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Download Complete")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    
                    Divider()
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .onAppear {
            // Check resume availability when view appears
            downloadManager.checkResumeAvailability(modelId: modelId)
        }
        .onChange(of: downloadManager.downloadedFile) { newValue in
            if let url = newValue {
                onDownloadComplete(url)
            }
        }
    }
}
