import SwiftUI
import Foundation

@MainActor
public class DownloadManager: ObservableObject {
    private let client = EdgenAIClient()
    private var downloadTask: Task<Void, Never>?
    
    @Published public var isDownloading = false
    @Published public var detailedProgress = DetailedProgress()
    @Published public var canResume = false
    @Published public var resumeInfo: String?
    @Published public var modelAlreadyExists = false
    @Published public var errorMessage: String?
    @Published public var downloadedFile: URL?
    @Published public var metadataFile: URL?
    
    public init() {}
    
    /// Check if resume is available for a model (safe - won't crash on missing files)
    public func checkResumeAvailability(modelId: String) {
        // First check if model already exists
        let existenceCheck = client.checkModelExists(modelId: modelId)
        if existenceCheck.exists {
            modelAlreadyExists = true
            downloadedFile = existenceCheck.modelURL
            metadataFile = existenceCheck.metadataURL
            canResume = false
            resumeInfo = nil
            return
        }
        
        // Reset model exists flag
        modelAlreadyExists = false
        
        // Use the safe getDownloadStatus method
        let status = client.getDownloadStatus(modelId: modelId)
        
        if status.hasProgress, let progressState = status.progressState {
            // Calculate progress based on actually existing chunks
            let existingCount = status.existingChunks.count
            let totalCount = progressState.totalChunks
            
            if existingCount > 0 {
                canResume = true
                detailedProgress.percentage = Double(existingCount) * 100.0 / Double(totalCount)
                
                resumeInfo = "Previous download: \(existingCount)/\(totalCount) chunks (\(detailedProgress.percentage)%)"
                
                EdgenLogger.debug("Resume available: \(existingCount)/\(totalCount) chunks")
                EdgenLogger.debug("Existing chunks: \(status.existingChunks.sorted())")
                EdgenLogger.debug("Missing chunks: \(status.missingChunks.sorted())")
            } else {
                // Progress state exists but no actual chunks - clean it up
                EdgenLogger.info("Progress state exists but no chunks found - will start fresh")
                canResume = false
                resumeInfo = nil
                detailedProgress = DetailedProgress()
            }
        } else {
            canResume = false
            resumeInfo = nil
            detailedProgress = DetailedProgress()
        }
    }
    
    /// Start or resume download
    public func startDownload(modelId: String) {
        guard !isDownloading else { return }
        
        // Clear previous errors
        errorMessage = nil
        downloadedFile = nil
        metadataFile = nil
        modelAlreadyExists = false
        
        isDownloading = true
        
        let client = self.client
        downloadTask = Task {
            // Hop to a background executor for the network call; state updates will marshal back to main actor
            let progressHandler: @Sendable (DetailedProgress) -> Void = { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.detailedProgress = progress
                    if progress.currentChunk > 0 {
                        self.resumeInfo = "Downloading: \(progress.currentChunk)/\(progress.totalChunks) chunks (\(progress.percentage)%)"
                    }
                }
            }
            do {
                let (modelURL, metadataURL) = try await client.downloadModel(modelId: modelId, onProgress: progressHandler)
                
                await MainActor.run {
                    self.downloadedFile = modelURL
                    self.metadataFile = metadataURL
                    self.isDownloading = false
                    self.canResume = false
                    self.resumeInfo = nil
                    self.detailedProgress.percentage = 100
                }
                EdgenLogger.info("Download completed successfully!")
                EdgenLogger.info("Model URL: \(modelURL.path)")
                EdgenLogger.info("Metadata URL: \(metadataURL.path)")
                
            } catch is CancellationError {
                await MainActor.run {
                    self.isDownloading = false
                    self.errorMessage = "Download cancelled"
                }
                EdgenLogger.info("Download cancelled by user")
                
            } catch let error as DownloadError {
                await MainActor.run {
                    self.isDownloading = false
                    self.errorMessage = error.localizedDescription
                }
                EdgenLogger.error("Download error: \(error)")
                await MainActor.run {
                    self.checkResumeAvailability(modelId: modelId)
                }
                
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.errorMessage = "Download failed: \(error.localizedDescription)"
                }
                EdgenLogger.error("Download failed: \(error)")
                await MainActor.run {
                    self.checkResumeAvailability(modelId: modelId)
                }
            }
        }
    }
    
    /// Cancel ongoing download and cleanup
    public func cancelDownload(modelId: String) {
        // Cancel the task
        downloadTask?.cancel()
        downloadTask = nil
        
        // Cleanup downloaded chunks
        client.cancelDownload(modelId: modelId)
        
        // Reset state
        isDownloading = false
        canResume = false
        resumeInfo = nil
        detailedProgress = DetailedProgress()
        errorMessage = nil
        
        EdgenLogger.info("Download cancelled and cleaned up")
    }
}

