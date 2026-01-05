import Foundation

// MARK: - Downloaded Model Data Model
public struct DownloadedModel: Identifiable {
    public let id = UUID()
    public let modelId: String
    public let modelURL: URL
    public let metadataURL: URL?
    public let metadata: ModelMetadata?
    public let fileSize: Int64
    public let isCompiled: Bool
    
    public var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    public var formattedDownloadDate: String {
        guard let date = metadata?.downloadDate else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
