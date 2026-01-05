import Foundation

// MARK: - Model Existence Check Result
public struct ModelExistenceResult {
    public let exists: Bool
    public let modelURL: URL?
    public let metadataURL: URL?
    public let metadata: ModelMetadata?
}

// MARK: - Detailed Progress
public struct DetailedProgress : Sendable {
    public var percentage: Double
    public var downloadedBytes: Int64
    public var totalBytes: Int64
    public var bytesPerSecond: Double
    public var estimatedTimeRemaining: TimeInterval
    public var currentChunk: Int
    public var totalChunks: Int
    public var phase: DownloadPhase
    
    public enum DownloadPhase : Sendable{
        case initializing
        case downloading
        case merging
        case validating
        case compiling
        case complete
    }
    
    public init(percentage: Double, downloadedBytes: Int64, totalBytes: Int64, bytesPerSecond: Double, estimatedTimeRemaining: TimeInterval, currentChunk: Int, totalChunks: Int, phase: DownloadPhase) {
        self.percentage = percentage
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.currentChunk = currentChunk
        self.totalChunks = totalChunks
        self.phase = phase
    }
    
    
    public init() {
        self.percentage = 0
        self.downloadedBytes = 0
        self.totalBytes = 0
        self.bytesPerSecond = 0.0
        self.estimatedTimeRemaining = 0
        self.currentChunk = 0
        self.totalChunks = 0
        self.phase = DownloadPhase.initializing
    }
}

// MARK: - Download Progress State
struct DownloadProgressState: Codable {
    let modelId: String
    let totalChunks: Int
    let validatedChunks: Set<Int>
    let chunkHashes: [Int: String]
    let hash: String
    let fileExt: String
    let modelName: String
    let version: String
    let description: String
    let category: String
    let totalBytes: Int64
    let lastUpdated: Date
    
    var isComplete: Bool {
        validatedChunks.count == totalChunks
    }
    
    var progress: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(validatedChunks.count) / Double(totalChunks)
    }
    
    func validateAllChunks(client: EdgenAIClient, modelId: String) -> Set<Int> {
        var valid = Set<Int>()
        // Only validate chunks that were marked as validated
        for chunkIndex in validatedChunks {
            if let expectedHash = chunkHashes[chunkIndex] {
                if client.validateChunk(modelId: modelId, chunkIndex: chunkIndex, expectedHash: expectedHash) {
                    valid.insert(chunkIndex)
                } else {
                    EdgenLogger.error("Chunk \(chunkIndex) failed validation - will be re-downloaded")
                }
            } else {
                EdgenLogger.warning("Chunk \(chunkIndex) marked as validated but no hash found")
            }
        }
        return valid
    }
}

// MARK: - Download Error
enum DownloadError: Error, LocalizedError {
    case networkError(Error, recoverable: Bool)
    case hashMismatch(chunkIndex: Int, recoverable: Bool)
    case diskError(Error, recoverable: Bool)
    case serverError(statusCode: Int, recoverable: Bool)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case chunkCorrupted(chunkIndex: Int)
    case downloadCancelled
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error, _):
            return "Network error: \(error.localizedDescription)"
        case .hashMismatch(let chunkIndex, _):
            return "Hash mismatch for chunk \(chunkIndex)"
        case .diskError(let error, _):
            return "Disk error: \(error.localizedDescription)"
        case .serverError(let statusCode, _):
            return "Server error: \(statusCode)"
        case .insufficientDiskSpace(let required, let available):
            return "Insufficient disk space. Required: \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), Available: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))"
        case .chunkCorrupted(let chunkIndex):
            return "Chunk \(chunkIndex) is corrupted"
        case .downloadCancelled:
            return "Download was cancelled"
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .networkError(_, let recoverable),
             .hashMismatch(_, let recoverable),
             .diskError(_, let recoverable),
             .serverError(_, let recoverable):
            return recoverable
        case .insufficientDiskSpace, .chunkCorrupted, .downloadCancelled:
            return false
        }
    }
}

// MARK: - Compilation Error
enum ModelCompilationError: Error {
    case compilationFailed(String)
    case moveFailed(String)
}

// MARK: - Download Statistics
class DownloadStatistics {
    private var startTime: Date?
    private var downloadedBytes: Int64 = 0
    private var lastUpdateTime: Date?
    private var lastDownloadedBytes: Int64 = 0
    
    func start() {
        startTime = Date()
        lastUpdateTime = Date()
    }
    
    func update(downloadedBytes: Int64) {
        self.downloadedBytes = downloadedBytes
    }
    
    func getBytesPerSecond() -> Double {
        guard let lastUpdate = lastUpdateTime else { return 0 }
        
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastUpdate)
        guard timeDiff > 0 else { return 0 }
        
        let bytesDiff = downloadedBytes - lastDownloadedBytes
        let bytesPerSecond = Double(bytesDiff) / timeDiff
        
        lastUpdateTime = now
        lastDownloadedBytes = downloadedBytes
        
        return bytesPerSecond
    }
    
    func getEstimatedTimeRemaining(totalBytes: Int64) -> TimeInterval {
        let bytesPerSecond = getBytesPerSecond()
        guard bytesPerSecond > 0 else { return 0 }
        
        let remainingBytes = totalBytes - downloadedBytes
        return Double(remainingBytes) / bytesPerSecond
    }
    
    func getDownloadedBytes() -> Int64 {
        return downloadedBytes
    }
}
