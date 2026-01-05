// MARK: - Hash Utility

import CryptoKit
import Foundation

class HashUtility {
    static func calculateFileHash(fileURL: URL) throws -> String {
        let bufferSize = 1024 * 1024 // 1MB buffer
        let file = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? file.close()
        }
        
        var hasher = SHA256()
        
        while autoreleasepool(invoking: {
            let data = file.readData(ofLength: bufferSize)
            if data.count > 0 {
                hasher.update(data: data)
                return true
            } else {
                return false
            }
        }) { }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    static func calculateDataHash(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Hash Validation Error
enum HashValidationError: Error {
    case chunkHashMismatch(expected: String, actual: String, chunkIndex: Int)
    case finalHashMismatch(expected: String, actual: String)
    
    var localizedDescription: String {
        switch self {
        case .chunkHashMismatch(let expected, let actual, let chunkIndex):
            return "Chunk \(chunkIndex) hash mismatch. Expected: \(expected), Got: \(actual)"
        case .finalHashMismatch(let expected, let actual):
            return "Final file hash mismatch. Expected: \(expected), Got: \(actual)"
        }
    }
}
