import Foundation
import SwiftUI
import CryptoKit
import CoreML

// Call EdgenAIConfig.initialize(accessKey:..., secretKey:...) at app launch (e.g., in AppDelegate)
actor EdgenAIConfig {
    static let shared = EdgenAIConfig()
    
    let apiEndpoint =
    "https://3fmm0thylf.execute-api.us-west-2.amazonaws.com/prod"
    private(set) var accessKey: String?
    private(set) var secretKey: String?
    
    func initialize(accessKey: String, secretKey: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
    }
}

// MARK: - Download Coordinator (for thread-safe chunk tracking)
actor DownloadCoordinator {
    private var validatedChunks: Set<Int>
    private var chunkSizes: [Int: Int64]
    
    init(validatedChunks: Set<Int>) {
        self.validatedChunks = validatedChunks
        self.chunkSizes = [:]
    }
    
    func isChunkValidated(_ chunkIndex: Int) -> Bool {
        return validatedChunks.contains(chunkIndex)
    }
    
    func markChunkAsValidated(_ chunkIndex: Int, size: Int64) {
        validatedChunks.insert(chunkIndex)
        chunkSizes[chunkIndex] = size
    }
    
    func getValidatedChunks() -> Set<Int> {
        return validatedChunks
    }
    
    func getChunkSizes() -> [Int: Int64] {
        return chunkSizes
    }
    
    func setChunkSize(_ chunkIndex: Int, size: Int64) {
        chunkSizes[chunkIndex] = size
    }
}

// MARK: - API Client
public class EdgenAIClient {

    public init() {}
    
    /// Call this at app launch to set API credentials.
    public static func initialize(accessKey: String, secretKey: String) {
        Task { await EdgenAIConfig.shared.initialize(accessKey: accessKey, secretKey: secretKey) }
    }
    
    private let maxConcurrentDownloads = 3
    private let maxRetries = 3
    private var downloadStats = DownloadStatistics()
    private var failedChunks = 0
    private var attemptedChunks = 0
    
    private var adaptiveConcurrency: Int {
        guard attemptedChunks > 0 else { return maxConcurrentDownloads }
        let failureRate = Double(failedChunks) / Double(attemptedChunks)
        if failureRate > 0.3 { return 1 }
        if failureRate > 0.1 { return 2 }
        return maxConcurrentDownloads
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func getAuthHeader() async -> String {
        let accessKey = await EdgenAIConfig.shared.accessKey
        let secretKey = await EdgenAIConfig.shared.secretKey
        guard let accessKey, let secretKey else {
            fatalError("EdgenAIConfig accessKey and secretKey must be set. Call EdgenAIConfig.initialize(...) at app launch.")
        }
        return "Bearer \(accessKey):\(secretKey)"
    }
    
    /// Get the download progress state file URL for a given model ID
    private func getProgressStateURL(modelId: String) -> URL {
        return documentsDirectory.appendingPathComponent("\(modelId)_progress")
    }
    
    /// Save download progress state
    private func saveProgressState(_ state: DownloadProgressState) throws {
        let url = getProgressStateURL(modelId: state.modelId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: url)
    }
    
    /// Load download progress state
    private func loadProgressState(modelId: String) -> DownloadProgressState? {
        let url = getProgressStateURL(modelId: modelId)
        guard fileExists(at: url) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DownloadProgressState.self, from: data)
        } catch {
            EdgenLogger.error("Failed to load progress state: \(error)")
            return nil
        }
    }
    
    /// Delete progress state file
    private func deleteProgressState(modelId: String) {
        let url = getProgressStateURL(modelId: modelId)
        safelyRemoveFile(at: url)
    }
    
    /// Get chunk file URL
    private func getChunkURL(modelId: String, chunkIndex: Int) -> URL {
        return documentsDirectory.appendingPathComponent("\(modelId)_chunk_\(chunkIndex)")
    }
    
    /// Check if a chunk file exists (for UI display purposes)
    func chunkFileExists(modelId: String, chunkIndex: Int) -> Bool {
        let chunkURL = getChunkURL(modelId: modelId, chunkIndex: chunkIndex)
        return fileExists(at: chunkURL)
    }
    
    /// Get chunk file URL for external access (be careful with this)
    func getChunkFileURL(modelId: String, chunkIndex: Int) -> URL {
        return getChunkURL(modelId: modelId, chunkIndex: chunkIndex)
    }
    
    /// Validate if a chunk exists and has the correct hash
    func validateChunk(modelId: String, chunkIndex: Int, expectedHash: String) -> Bool {
        let chunkURL = getChunkURL(modelId: modelId, chunkIndex: chunkIndex)
        
        guard fileExists(at: chunkURL) else {
            EdgenLogger.warning("Chunk \(chunkIndex) file does not exist at: \(chunkURL.path)")
            return false
        }
        
        do {
            let chunkData = try Data(contentsOf: chunkURL)
            let calculatedHash = HashUtility.calculateDataHash(data: chunkData)
            let isValid = calculatedHash == expectedHash
            
            if !isValid {
                EdgenLogger.error("Chunk \(chunkIndex) hash validation failed. Expected: \(expectedHash), Got: \(calculatedHash)")
            }
            
            return isValid
        } catch {
            EdgenLogger.error("Failed to validate chunk \(chunkIndex): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Clean up incomplete download chunks
    private func cleanupIncompleteDownload(modelId: String, totalChunks: Int) {
        for index in 0..<totalChunks {
            let chunkURL = getChunkURL(modelId: modelId, chunkIndex: index)
            safelyRemoveFile(at: chunkURL)
        }
        deleteProgressState(modelId: modelId)
    }
    
    /// Get the model file URL for a given model ID
    private func getModelFileURL(modelId: String) -> URL {
        // Check if compiled model exists first
        let compiledURL = documentsDirectory.appendingPathComponent("\(modelId).mlmodelc")
        if fileExists(at: compiledURL) {
            return compiledURL
        }
        
        // Otherwise return base model path
        return documentsDirectory.appendingPathComponent(modelId)
    }
    
    /// Get the metadata file URL for a given model ID
    private func getMetadataFileURL(modelId: String) -> URL {
        return documentsDirectory.appendingPathComponent("\(modelId)_metadata")
    }
    
    /// Validate available disk space
    private func validateDiskSpace(requiredBytes: Int64) throws {
        let fileURL = documentsDirectory
        
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: fileURL.path)
            
            if let freeSpace = attributes[.systemFreeSize] as? Int64 {
                // Require 2x space for safety (chunks + merged file)
                let requiredSpace = requiredBytes * 2
                if freeSpace < requiredSpace {
                    throw DownloadError.insufficientDiskSpace(required: requiredSpace, available: freeSpace)
                }
            }
        } catch let error as DownloadError {
            throw error
        } catch {
            throw DownloadError.diskError(error, recoverable: false)
        }
    }
    
    /// Check if a model exists locally and return its path
    public func checkModelExists(modelId: String) -> ModelExistenceResult {
        // Check for compiled model (.mlmodelc)
        let compiledURL = documentsDirectory.appendingPathComponent("\(modelId).mlmodelc")
        let compiledExists = fileExists(at: compiledURL)
        
        // Check for regular model (no extension)
        let regularURL = documentsDirectory.appendingPathComponent(modelId)
        let regularExists = fileExists(at: regularURL)
        
        let modelURL = compiledExists ? compiledURL : (regularExists ? regularURL : nil)
        let modelExists = compiledExists || regularExists
        
        let metadataURL = getMetadataFileURL(modelId: modelId)
        let metadataExists = fileExists(at: metadataURL)
        
        if modelExists, let foundModelURL = modelURL {
            var metadata: ModelMetadata?
            if metadataExists {
                do {
                    let data = try Data(contentsOf: metadataURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    metadata = try decoder.decode(ModelMetadata.self, from: data)
                } catch {
                    // Metadata exists but couldn't be parsed
                    EdgenLogger.error("Failed to parse metadata: \(error)")
                }
            }
            
            return ModelExistenceResult(
                exists: true,
                modelURL: foundModelURL,
                metadataURL: metadataExists ? metadataURL : nil,
                metadata: metadata
            )
        }
        
        return ModelExistenceResult(exists: false, modelURL: nil, metadataURL: nil, metadata: nil)
    }
    
    /// Check if a model with specific name exists locally by searching through all metadata files
    func checkModelExistsByName(modelName: String) -> ModelExistenceResult {
        // Search through all metadata files to find matching model name
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: nil
            )
            
            // Find all metadata files (those ending with _metadata)
            let metadataFiles = fileURLs.filter { $0.lastPathComponent.hasSuffix("_metadata") }
            
            for metadataURL in metadataFiles {
                do {
                    let data = try Data(contentsOf: metadataURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let metadata = try decoder.decode(ModelMetadata.self, from: data)
                    
                    // Check if this is the model we're looking for
                    if metadata.modelName == modelName {
                        // Use the modelId from metadata to get the correct model file path
                        let modelURL = getModelFileURL(modelId: metadata.modelId)
                        
                        // Verify the model file actually exists
                        if fileExists(at: modelURL) {
                            return ModelExistenceResult(
                                exists: true,
                                modelURL: modelURL,
                                metadataURL: metadataURL,
                                metadata: metadata
                            )
                        }
                    }
                } catch {
                    // Skip invalid metadata files
                    continue
                }
            }
        } catch {
            EdgenLogger.error("Error reading directory: \(error)")
            return ModelExistenceResult(exists: false, modelURL: nil, metadataURL: nil, metadata: nil)
        }
        
        return ModelExistenceResult(exists: false, modelURL: nil, metadataURL: nil, metadata: nil)
    }
    
    /// Get comprehensive download status for a model (safe for UI display)
    func getDownloadStatus(modelId: String) -> (
        hasProgress: Bool,
        progressState: DownloadProgressState?,
        existingChunks: Set<Int>,
        missingChunks: Set<Int>
    ) {
        guard let progressState = loadProgressState(modelId: modelId) else {
            return (hasProgress: false, progressState: nil, existingChunks: [], missingChunks: [])
        }
        
        // Check which chunks actually exist on disk
        var existingChunks = Set<Int>()
        for chunkIndex in 0..<progressState.totalChunks {
            if chunkFileExists(modelId: modelId, chunkIndex: chunkIndex) {
                existingChunks.insert(chunkIndex)
            }
        }
        
        let allChunks = Set(0..<progressState.totalChunks)
        let missingChunks = allChunks.subtracting(existingChunks)
        
        return (
            hasProgress: true,
            progressState: progressState,
            existingChunks: existingChunks,
            missingChunks: missingChunks
        )
    }
    
    /// Get download progress for a model
    func getDownloadProgress(modelId: String) -> DownloadProgressState? {
        return loadProgressState(modelId: modelId)
    }
    
    /// Cancel and cleanup an incomplete download
    func cancelDownload(modelId: String) {
        guard let progressState = loadProgressState(modelId: modelId) else {
            return
        }
        
        cleanupIncompleteDownload(modelId: modelId, totalChunks: progressState.totalChunks)
        EdgenLogger.debug("Cancelled and cleaned up download for model: \(modelId)")
    }
    
    /// Download a chunk with retry logic
    private static func downloadChunkWithRetry(
        session: URLSession,
        urlInfo: DownloadUrlInfo,
        modelId: String
    ) async throws -> Data {
        var lastError: Error?
        
        for attempt in 0..<3 {
            do {
                guard let downloadURL = URL(string: urlInfo.urlInfo.url) else {
                    throw URLError(.badURL)
                }
                
                var downloadRequest = URLRequest(url: downloadURL)
                downloadRequest.httpMethod = "GET"
                downloadRequest.timeoutInterval = 60
                
                let (fileURL, downloadHttpResponse) = try await session.download(for: downloadRequest)
                
                guard let s3HttpResponse = downloadHttpResponse as? HTTPURLResponse else {
                    throw DownloadError.serverError(statusCode: 0, recoverable: true)
                }
                
                guard s3HttpResponse.statusCode == 200 else {
                    let recoverable = s3HttpResponse.statusCode >= 500 || s3HttpResponse.statusCode == 429
                    throw DownloadError.serverError(statusCode: s3HttpResponse.statusCode, recoverable: recoverable)
                }
                
                // Validate chunk hash
                let chunkData = try Data(contentsOf: fileURL)
                let calculatedHash = HashUtility.calculateDataHash(data: chunkData)
                
                if calculatedHash != urlInfo.chunkHash {
                    throw DownloadError.hashMismatch(chunkIndex: urlInfo.chunkIndex, recoverable: true)
                }
                
                // Success - move chunk to permanent location
                let chunkURL = EdgenAIClient().getChunkURL(modelId: modelId, chunkIndex: urlInfo.chunkIndex)
                EdgenAIClient().safelyRemoveFile(at: chunkURL)
                EdgenAIClient().safelyMoveFile(from: fileURL, to: chunkURL)
                
                return chunkData
                
            } catch {
                lastError = error
                
                // Check if error is recoverable
                let isRecoverable: Bool
                if let downloadError = error as? DownloadError {
                    isRecoverable = downloadError.isRecoverable
                } else if error is URLError {
                    isRecoverable = true
                } else {
                    isRecoverable = false
                }
                
                if !isRecoverable || attempt >= 2 {
                    throw error
                }
                
                // Exponential backoff
                let delay = pow(2.0, Double(attempt))
                EdgenLogger.info("Chunk \(urlInfo.chunkIndex) failed (attempt \(attempt + 1)/3), retrying in \(delay)s...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? DownloadError.networkError(URLError(.unknown), recoverable: false)
    }
    
    /// Compile a Core ML model from .mlmodel to .mlmodelc
    private func compileMLModel(sourceURL: URL, modelId: String) async throws -> URL {
        EdgenLogger.debug("Compiling Core ML model...")
        
        // Compile the model (returns a temporary URL)
        let tempCompiledURL = try await Task {
            try MLModel.compileModel(at: sourceURL)
        }.value
        
        // Create permanent location in Documents
        let permanentCompiledURL = documentsDirectory.appendingPathComponent("\(modelId).mlmodelc")
        
        // Remove old compiled version if exists
        safelyRemoveFile(at: permanentCompiledURL)
        
        // Move compiled model to permanent location
        do {
            try FileManager.default.moveItem(at: tempCompiledURL, to: permanentCompiledURL)
        } catch {
            throw ModelCompilationError.moveFailed("Failed to move compiled model: \(error.localizedDescription)")
        }
        
        // Delete the source .mlmodel file to save space
        safelyRemoveFile(at: sourceURL)
        
        EdgenLogger.info("Model compiled successfully to: \(permanentCompiledURL.path)")
        
        return permanentCompiledURL
    }

    func downloadModel(
        modelId: String,
        onProgress: @escaping (DetailedProgress) -> Void = { _ in }
    ) async throws -> (modelURL: URL, metadataURL: URL) {
        
        return try await withTaskCancellationHandler {
            try await performDownload(modelId: modelId, onProgress: onProgress)
        } onCancel: { [modelId] in
            Task.detached {
                let client = EdgenAIClient()
                client.cancelDownload(modelId: modelId)
            }
        }
    }
    
    // MARK: - Download Initialization
    
    /// Initialize download by requesting URLs and preparing progress state
    private func initializeDownload(
        modelId: String,
        onProgress: @escaping (DetailedProgress) -> Void
    ) async throws -> (response: DownloadResponse, progressState: DownloadProgressState, sortedChunks: [DownloadUrlInfo]) {
        
        // Report initializing phase
        onProgress(DetailedProgress(
            percentage: 0,
            downloadedBytes: 0,
            totalBytes: 0,
            bytesPerSecond: 0,
            estimatedTimeRemaining: 0,
            currentChunk: 0,
            totalChunks: 0,
            phase: .initializing
        ))
        
        let apiEndpoint = EdgenAIConfig.shared.apiEndpoint
        guard let url = URL(string: "\(apiEndpoint)/initDownload") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(await getAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = DownloadRequest(modelId: modelId)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            EdgenLogger.error("\(response)")
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            EdgenLogger.error("\(httpResponse)")
            throw URLError.fromHTTPStatusCode(httpResponse.statusCode)
        }

        let downloadResponse = try JSONDecoder().decode(DownloadResponse.self, from: data)
        let sortedChunks = downloadResponse.urlInfoList.sorted { $0.chunkIndex < $1.chunkIndex }
        
        // Prepare progress state
        let progressState = try prepareProgressState(
            modelId: modelId,
            downloadResponse: downloadResponse,
            sortedChunks: sortedChunks
        )
        
        return (downloadResponse, progressState, sortedChunks)
    }
    
    /// Prepare or resume progress state for download
    private func prepareProgressState(
        modelId: String,
        downloadResponse: DownloadResponse,
        sortedChunks: [DownloadUrlInfo]
    ) throws -> DownloadProgressState {
        
        let chunkHashes = Dictionary(uniqueKeysWithValues: sortedChunks.map { ($0.chunkIndex, $0.chunkHash) })
        var progressState = loadProgressState(modelId: modelId)
        
        // Validate existing progress state
        if let existingState = progressState {
            if existingState.hash != downloadResponse.hash ||
               existingState.totalChunks != sortedChunks.count {
                EdgenLogger.warning("Model metadata changed, starting fresh download")
                cleanupIncompleteDownload(modelId: modelId, totalChunks: existingState.totalChunks)
                progressState = nil
            } else {
                // Validate all chunks marked as complete
                let validatedChunks = existingState.validateAllChunks(client: self, modelId: modelId)
                
                if validatedChunks.count != existingState.validatedChunks.count {
                    let updatedState = DownloadProgressState(
                        modelId: existingState.modelId,
                        totalChunks: existingState.totalChunks,
                        validatedChunks: validatedChunks,
                        chunkHashes: existingState.chunkHashes,
                        hash: existingState.hash,
                        fileExt: existingState.fileExt,
                        modelName: existingState.modelName,
                        version: existingState.version,
                        description: existingState.description,
                        category: existingState.category,
                        totalBytes: existingState.totalBytes,
                        lastUpdated: Date()
                    )
                    progressState = updatedState
                    try saveProgressState(updatedState)
                }
                
                EdgenLogger.debug("Resuming download: \(validatedChunks.count)/\(existingState.totalChunks) chunks validated")
            }
        }
        
        // Create new progress state if needed
        if progressState == nil {
            progressState = DownloadProgressState(
                modelId: modelId,
                totalChunks: sortedChunks.count,
                validatedChunks: [],
                chunkHashes: chunkHashes,
                hash: downloadResponse.hash,
                fileExt: downloadResponse.fileExt,
                modelName: downloadResponse.modelName,
                version: downloadResponse.version,
                description: downloadResponse.description ?? "",
                category: downloadResponse.category ?? "",
                totalBytes: 0,
                lastUpdated: Date()
            )
            try saveProgressState(progressState!)
        }
        
        guard let finalState = progressState else {
            throw URLError(.unknown)
        }
        
        return finalState
    }
    
    // MARK: - Chunk Download Management
    
    /// Download all chunks concurrently with progress tracking
    private func downloadAllChunks(
        sortedChunks: [DownloadUrlInfo],
        progressState: DownloadProgressState,
        modelId: String,
        downloadResponse: DownloadResponse,
        onProgress: @escaping (DetailedProgress) -> Void
    ) async throws -> (DownloadProgressState, Int64) {
        
        let totalChunks = sortedChunks.count
        var validatedChunks = progressState.validatedChunks
        var totalBytes: Int64 = 0
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        
        // Reset download statistics
        downloadStats = DownloadStatistics()
        downloadStats.start()
        failedChunks = 0
        attemptedChunks = 0
        
        // Log download plan
        let chunksToDownload = sortedChunks.filter { !validatedChunks.contains($0.chunkIndex) }
        if chunksToDownload.isEmpty {
            EdgenLogger.debug("All chunks already downloaded, proceeding to merge...")
        } else {
            EdgenLogger.debug("Download plan: \(chunksToDownload.count) chunks to download")
            EdgenLogger.debug("Already have: \(validatedChunks.sorted().map { $0 + 1 })")
            EdgenLogger.debug("Need to download: \(chunksToDownload.map { $0.chunkIndex + 1 }.sorted())")
        }
        
        // Download chunks concurrently
        let coordinator = DownloadCoordinator(validatedChunks: validatedChunks)
        
        // Initialize chunk sizes for already downloaded chunks
        for chunkIndex in validatedChunks {
            let chunkURL = getChunkURL(modelId: modelId, chunkIndex: chunkIndex)
            if fileExists(at: chunkURL),
               let attributes = try? FileManager.default.attributesOfItem(atPath: chunkURL.path),
               let fileSize = attributes[.size] as? Int64 {
                await coordinator.setChunkSize(chunkIndex, size: fileSize)
            }
        }
        
        var currentProgressState = progressState
        
        try await withThrowingTaskGroup(of: (Int, Int64).self) { group in
            var downloadingChunks = 0
            var nextChunkIndex = 0
            var completedChunks = validatedChunks.count
            
            // Report initial progress for resumed downloads
            if completedChunks > 0 {
                let chunkSizes = await coordinator.getChunkSizes()
                let currentDownloadedBytes = chunkSizes.values.reduce(0, +)
                let estimatedTotalBytes = (currentDownloadedBytes * Int64(totalChunks)) / Int64(completedChunks)
                totalBytes = estimatedTotalBytes
                
                let downloadProgress = downloadResponse.fileExt.lowercased() == "mlmodel" ? 80 : 90
                let percentage = (Double(completedChunks) / Double(totalChunks)) * Double(downloadProgress)
                
                onProgress(DetailedProgress(
                    percentage: percentage,
                    downloadedBytes: currentDownloadedBytes,
                    totalBytes: estimatedTotalBytes,
                    bytesPerSecond: 0,
                    estimatedTimeRemaining: 0,
                    currentChunk: completedChunks,
                    totalChunks: totalChunks,
                    phase: .downloading
                ))
            }
            
            // Start initial batch of downloads
            EdgenLogger.debug("Starting initial batch with concurrency: \(adaptiveConcurrency)")
            while nextChunkIndex < sortedChunks.count && downloadingChunks < adaptiveConcurrency {
                let urlInfo = sortedChunks[nextChunkIndex]
                let isValidated = await coordinator.isChunkValidated(urlInfo.chunkIndex)
                EdgenLogger.debug("Checking chunk \(urlInfo.chunkIndex) (\(urlInfo.chunkIndex + 1)/\(totalChunks)): validated=\(isValidated), downloadingChunks=\(downloadingChunks)")
                
                nextChunkIndex += 1
                
                if isValidated {
                    EdgenLogger.debug("Skipping chunk \(urlInfo.chunkIndex + 1)/\(totalChunks) - already downloaded")
                    continue
                }
                
                // Insert immutable captures for concurrency and @Sendable closure
                let urlInfoCopy = urlInfo
                let sessionCopy = session
                let modelIdCopy = modelId
                
                EdgenLogger.debug("Queueing chunk \(urlInfoCopy.chunkIndex + 1)/\(totalChunks) for download")
                group.addTask(priority: nil) { @Sendable in
                    try Task.checkCancellation()
                    
                    EdgenLogger.debug("Downloading chunk \(urlInfoCopy.chunkIndex + 1)/\(totalChunks)...")
                    let chunkData = try await EdgenAIClient.downloadChunkWithRetry(
                        session: sessionCopy,
                        urlInfo: urlInfoCopy,
                        modelId: modelIdCopy
                    )
                    
                    return (urlInfoCopy.chunkIndex, Int64(chunkData.count))
                }
                
                downloadingChunks += 1
            }
            
            // Process completed downloads and start new ones
            while let result = try await group.next() {
                try Task.checkCancellation()
                
                let (chunkIndex, chunkSize) = result
                
                // Mark chunk as validated in coordinator
                await coordinator.markChunkAsValidated(chunkIndex, size: chunkSize)
                completedChunks += 1
                
                // Calculate total bytes from downloaded chunks
                let chunkSizes = await coordinator.getChunkSizes()
                let currentDownloadedBytes = chunkSizes.values.reduce(0, +)
                let estimatedTotalBytes = completedChunks > 0 ?
                    (currentDownloadedBytes * Int64(totalChunks)) / Int64(completedChunks) :
                    currentDownloadedBytes
                totalBytes = estimatedTotalBytes
                
                downloadStats.update(downloadedBytes: currentDownloadedBytes)
                
                // Get updated validated chunks for saving progress
                validatedChunks = await coordinator.getValidatedChunks()
                
                // Save progress state after each successful chunk
                currentProgressState = DownloadProgressState(
                    modelId: currentProgressState.modelId,
                    totalChunks: currentProgressState.totalChunks,
                    validatedChunks: validatedChunks,
                    chunkHashes: currentProgressState.chunkHashes,
                    hash: currentProgressState.hash,
                    fileExt: currentProgressState.fileExt,
                    modelName: currentProgressState.modelName,
                    version: currentProgressState.version,
                    description: currentProgressState.description,
                    category: currentProgressState.category,
                    totalBytes: currentProgressState.totalBytes,
                    lastUpdated: Date()
                )
                try saveProgressState(currentProgressState)
                
                // Update progress
                let downloadProgress = downloadResponse.fileExt.lowercased() == "mlmodel" ? 80 : 90
                let percentage = (Double(completedChunks) / Double(totalChunks)) * Double(downloadProgress)
                
                onProgress(DetailedProgress(
                    percentage: percentage,
                    downloadedBytes: currentDownloadedBytes,
                    totalBytes: totalBytes,
                    bytesPerSecond: downloadStats.getBytesPerSecond(),
                    estimatedTimeRemaining: downloadStats.getEstimatedTimeRemaining(totalBytes: totalBytes),
                    currentChunk: completedChunks,
                    totalChunks: totalChunks,
                    phase: .downloading
                ))
                
                // Start next download
                downloadingChunks -= 1
                EdgenLogger.debug("Chunk completed. downloadingChunks now: \(downloadingChunks)")
                
                // Keep trying to find a chunk that needs downloading
                while nextChunkIndex < sortedChunks.count {
                    let urlInfo = sortedChunks[nextChunkIndex]
                    let isValidated = await coordinator.isChunkValidated(urlInfo.chunkIndex)
                    EdgenLogger.debug("Checking next chunk \(urlInfo.chunkIndex) (\(urlInfo.chunkIndex + 1)/\(totalChunks)): validated=\(isValidated)")
                    
                    nextChunkIndex += 1
                    
                    if isValidated {
                        EdgenLogger.debug("Skipping chunk \(urlInfo.chunkIndex + 1)/\(totalChunks) - already downloaded")
                        continue
                    }
                    
                    // Insert immutable captures for concurrency and @Sendable closure
                    let urlInfoCopy = urlInfo
                    let sessionCopy = session
                    let modelIdCopy = modelId
                    
                    EdgenLogger.debug("Queueing chunk \(urlInfoCopy.chunkIndex + 1)/\(totalChunks) for download")
                    group.addTask(priority: nil) { @Sendable in
                        try Task.checkCancellation()
                        
                        EdgenLogger.debug("Downloading chunk \(urlInfoCopy.chunkIndex + 1)/\(totalChunks)...")
                        let chunkData = try await EdgenAIClient.downloadChunkWithRetry(
                            session: sessionCopy,
                            urlInfo: urlInfoCopy,
                            modelId: modelIdCopy
                        )
                        
                        return (urlInfoCopy.chunkIndex, Int64(chunkData.count))
                    }
                    
                    downloadingChunks += 1
                    EdgenLogger.debug("Queued chunk \(urlInfoCopy.chunkIndex + 1). downloadingChunks now: \(downloadingChunks)")
                    break
                }
            }
        }
        
        return (currentProgressState, totalBytes)
    }
    
    // MARK: - File Merging and Validation
    
    /// Merge all chunks into final file and validate
    private func mergeAndValidateChunks(
        modelId: String,
        totalChunks: Int,
        chunkHashes: [Int: String],
        downloadResponse: DownloadResponse,
        totalBytes: Int64,
        onProgress: @escaping (DetailedProgress) -> Void
    ) async throws -> URL {
        
        try Task.checkCancellation()
        
        EdgenLogger.debug("Merging chunks into final file...")
        
        let mergeProgress = downloadResponse.fileExt.lowercased() == "mlmodel" ? 85.0 : 95.0
        onProgress(DetailedProgress(
            percentage: mergeProgress,
            downloadedBytes: totalBytes,
            totalBytes: totalBytes,
            bytesPerSecond: 0,
            estimatedTimeRemaining: 0,
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            phase: .merging
        ))
        
        let tempDestinationURL: URL
        
        // If it's an mlmodel, add the extension temporarily for merging
        if downloadResponse.fileExt.lowercased() == "mlmodel" {
            tempDestinationURL = documentsDirectory.appendingPathComponent("\(modelId).mlmodel")
        } else {
            tempDestinationURL = getModelFileURL(modelId: modelId)
        }
        
        safelyRemoveFile(at: tempDestinationURL)
        
        // Create final file
        FileManager.default.createFile(atPath: tempDestinationURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempDestinationURL)
        
        defer {
            try? fileHandle.close()
        }
        
        // Merge chunks in order with validation
        for chunkIndex in 0..<totalChunks {
            try Task.checkCancellation()
            
            let chunkURL = getChunkURL(modelId: modelId, chunkIndex: chunkIndex)
            let chunkData = try Data(contentsOf: chunkURL)
            
            // Re-validate chunk hash before writing
            if let expectedHash = chunkHashes[chunkIndex] {
                let actualHash = HashUtility.calculateDataHash(data: chunkData)
                guard actualHash == expectedHash else {
                    throw DownloadError.chunkCorrupted(chunkIndex: chunkIndex)
                }
            }
            
            fileHandle.write(chunkData)
        }
        
        try Task.checkCancellation()
        
        // Validate final file hash
        EdgenLogger.debug("Validating final file hash...")
        
        let validateProgress = downloadResponse.fileExt.lowercased() == "mlmodel" ? 88.0 : 98.0
        onProgress(DetailedProgress(
            percentage: validateProgress,
            downloadedBytes: totalBytes,
            totalBytes: totalBytes,
            bytesPerSecond: 0,
            estimatedTimeRemaining: 0,
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            phase: .validating
        ))
        
        let finalHash = try HashUtility.calculateFileHash(fileURL: tempDestinationURL)
        
        if finalHash != downloadResponse.hash {
            // Clean up invalid file
            safelyRemoveFile(at: tempDestinationURL)
            throw HashValidationError.finalHashMismatch(
                expected: downloadResponse.hash,
                actual: finalHash
            )
        }
        
        // Clean up chunk files after successful merge and validation
        for chunkIndex in 0..<totalChunks {
            let chunkURL = getChunkURL(modelId: modelId, chunkIndex: chunkIndex)
            safelyRemoveFile(at: chunkURL)
        }
        
        return tempDestinationURL
    }
    
    // MARK: - Metadata Management
    
    /// Save model metadata to disk
    private func saveModelMetadata(
        modelId: String,
        downloadResponse: DownloadResponse
    ) throws -> URL {
        
        let metadata = ModelMetadata(
            modelName: downloadResponse.modelName,
            modelId: downloadResponse.modelId,
            version: downloadResponse.version,
            description: downloadResponse.description ?? "",
            category: downloadResponse.category ?? "",
            hash: downloadResponse.hash,
            downloadDate: Date()
        )
        
        let metadataURL = getMetadataFileURL(modelId: modelId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataURL)
        
        return metadataURL
    }
    
    // MARK: - Main Download Flow
    
    private func performDownload(
        modelId: String,
        onProgress: @escaping (DetailedProgress) -> Void
    ) async throws -> (modelURL: URL, metadataURL: URL) {
        
        // Check if task was cancelled before starting
        try Task.checkCancellation()
        
        // Check if model already exists (quick return)
        let existenceCheck = checkModelExists(modelId: modelId)
        if existenceCheck.exists, let modelURL = existenceCheck.modelURL, let metadataURL = existenceCheck.metadataURL {
            EdgenLogger.debug("Model already exists at: \(modelURL.path)")
            return (modelURL: modelURL, metadataURL: metadataURL)
        }
        
        // Step 1: Initialize download
        let (downloadResponse, initialProgressState, sortedChunks) = try await initializeDownload(
            modelId: modelId,
            onProgress: onProgress
        )
        
        let totalChunks = sortedChunks.count
        let chunkHashes = Dictionary(uniqueKeysWithValues: sortedChunks.map { ($0.chunkIndex, $0.chunkHash) })
        
        // Step 2: Download all chunks
        let (_, totalBytes) = try await downloadAllChunks(
            sortedChunks: sortedChunks,
            progressState: initialProgressState,
            modelId: modelId,
            downloadResponse: downloadResponse,
            onProgress: onProgress
        )
        
        // Step 3: Merge and validate chunks
        var tempDestinationURL = try await mergeAndValidateChunks(
            modelId: modelId,
            totalChunks: totalChunks,
            chunkHashes: chunkHashes,
            downloadResponse: downloadResponse,
            totalBytes: totalBytes,
            onProgress: onProgress
        )
        
        try Task.checkCancellation()
        
        // Step 4: Compile if it's a Core ML model
        if downloadResponse.fileExt.lowercased() == "mlmodel" {
            onProgress(DetailedProgress(
                percentage: 90,
                downloadedBytes: totalBytes,
                totalBytes: totalBytes,
                bytesPerSecond: 0,
                estimatedTimeRemaining: 0,
                currentChunk: totalChunks,
                totalChunks: totalChunks,
                phase: .compiling
            ))
            
            tempDestinationURL = try await compileMLModel(sourceURL: tempDestinationURL, modelId: modelId)
        }
        
        try Task.checkCancellation()
        
        // Step 5: Save metadata
        let metadataURL = try saveModelMetadata(
            modelId: modelId,
            downloadResponse: downloadResponse
        )
        
        // Step 6: Delete progress state file after successful completion
        deleteProgressState(modelId: modelId)
        
        // Final progress update
        onProgress(DetailedProgress(
            percentage: 100,
            downloadedBytes: totalBytes,
            totalBytes: totalBytes,
            bytesPerSecond: 0,
            estimatedTimeRemaining: 0,
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            phase: .complete
        ))
        
        EdgenLogger.info("Download completed successfully!")
        
        return (modelURL: tempDestinationURL, metadataURL: metadataURL)
    }
    
    // MARK: - Helper Methods for File Operations
    
    private func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    
    private func safelyRemoveFile(at url: URL) {
        do {
            if fileExists(at: url) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            EdgenLogger.warning("Failed to remove file at \(url.path): \(error)")
        }
    }
    
    private func safelyMoveFile(from: URL, to: URL) {
        do {
            safelyRemoveFile(at: to)
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            EdgenLogger.warning("Failed to move file from \(from.path) to \(to.path): \(error)")
        }
    }
}

/*
 USAGE EXAMPLES:
 
 let client = EdgenAIClient()

 // Check by model ID
 let result = client.checkModelExists(modelId: "cf53f0dd94ba40c598099be45d66f28f")
 if result.exists {
     print("Model path: \(result.modelURL?.path ?? "")")
     print("Metadata path: \(result.metadataURL?.path ?? "")")
     print("Model name: \(result.metadata?.modelName ?? "")")
 }

 // Check by model name (searches through metadata files)
 let nameResult = client.checkModelExistsByName(modelName: "llama-3.2-1b-instruct")
 if nameResult.exists {
     print("Model path: \(nameResult.modelURL?.path ?? "")")
     print("Model ID: \(nameResult.metadata?.modelId ?? "")")
 }
 
 // Download with detailed progress
 Task {
     do {
         let (modelURL, metadataURL) = try await client.downloadModel(modelId: "model_id_here") { progress in
             print("Phase: \(progress.phase)")
             print("Progress: \(progress.percentage)%")
             print("Speed: \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytesPerSecond), countStyle: .file))/s")
             print("ETA: \(Int(progress.estimatedTimeRemaining))s")
             print("Chunk: \(progress.currentChunk)/\(progress.totalChunks)")
         }
         print("Downloaded to: \(modelURL.path)")
     } catch {
         print("Download failed: \(error.localizedDescription)")
     }
 }
 
 // Check download progress
 if let progress = client.getDownloadProgress(modelId: "model_id_here") {
     print("Download progress: \(Int(progress.progress * 100))%")
     print("Validated chunks: \(progress.validatedChunks.count)/\(progress.totalChunks)")
 }
 
 // Cancel incomplete download
 client.cancelDownload(modelId: "model_id_here")
 */

