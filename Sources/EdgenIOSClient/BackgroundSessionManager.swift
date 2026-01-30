import Foundation

/// Background session manager that handles URLSession events for background downloads.
/// This is automatically used by EdgenAIClient - no manual setup required.
public final class BackgroundSessionManager: NSObject, @unchecked Sendable {
    
    /// Shared instance used by EdgenAIClient
    public static let shared = BackgroundSessionManager()
    
    private let queue = DispatchQueue(label: "com.edgenai.backgroundsession", attributes: .concurrent)
    private var activeSessions: [String: URLSession] = [:]
    private var completionHandlers: [String: @Sendable () -> Void] = [:]
    
    private override init() {
        super.init()
    }
    
    /// Get or create a background session with the given identifier
    public func session(identifier: String) -> URLSession {
        queue.sync {
            if let existingSession = activeSessions[identifier] {
                return existingSession
            }
            
            let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = true
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 300
            
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            queue.async(flags: .barrier) { [weak self] in
                self?.activeSessions[identifier] = session
            }
            
            return session
        }
    }
    
    /// Store completion handler for a session
    public func storeCompletionHandler(_ handler: @escaping @Sendable () -> Void, for identifier: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.completionHandlers[identifier] = handler
        }
    }
    
    /// Handle background events - call this from AppDelegate
    public func handleBackgroundEvents(forSession identifier: String, completionHandler: @escaping @Sendable () -> Void) {
        storeCompletionHandler(completionHandler, for: identifier)
        
        // Recreate session to receive events
        _ = session(identifier: identifier)
    }
    
    /// Invalidate a session when download completes
    public func invalidateSession(identifier: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.activeSessions[identifier]?.finishTasksAndInvalidate()
            self?.activeSessions.removeValue(forKey: identifier)
        }
    }
}

// MARK: - URLSession Delegate

extension BackgroundSessionManager: URLSessionDelegate, URLSessionDownloadDelegate {
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        queue.sync {
            guard let identifier = session.configuration.identifier,
                  let completionHandler = completionHandlers[identifier] else {
                return
            }
            
            queue.async(flags: .barrier) { [weak self] in
                // Call the system completion handler on main thread
                DispatchQueue.main.async {
                    completionHandler()
                }
                self?.completionHandlers.removeValue(forKey: identifier)
            }
            
            print("✅ Background download completed for session: \(identifier)")
        }
    }
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // File downloaded to temporary location
        // EdgenAIClient handles moving it to permanent location
    }
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Progress tracking happens in EdgenAIClient
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ Download task failed: \(error.localizedDescription)")
        }
    }
}
