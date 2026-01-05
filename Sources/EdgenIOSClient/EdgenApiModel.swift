// MARK: - Model Download Request

import Foundation
struct DownloadRequest: Codable {
    let modelId: String
}

// MARK: - Signed URL Info
struct SignedUrlInfo: Codable {
    let url: String
    let expiration: Int64
}

// MARK: - Download URL Info
struct DownloadUrlInfo: Codable {
    let chunkIndex: Int
    let urlInfo: SignedUrlInfo
    let chunkHash: String
}

// MARK: - Download Response
struct DownloadResponse: Codable {
    let urlInfoList: [DownloadUrlInfo]
    let hash: String
    let modelName: String
    let modelId: String
    let version: String
    let description: String?
    let category: String?
    let fileExt: String
}

// MARK: - Model Metadata
public struct ModelMetadata: Codable {
    public let modelName: String
    public let modelId: String
    public let version: String
    public let description: String
    public let category: String
    public let hash: String
    public let downloadDate: Date
}

// MARK: - Download Status
public struct DownloadStatus: Codable {
    public let status: String
    public let progress: Int
    public let message: String?
}
