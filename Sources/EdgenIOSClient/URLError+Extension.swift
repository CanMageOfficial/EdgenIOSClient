import Foundation

extension URLError {
    /// Creates a URLError from an HTTP status code with detailed error information
    /// - Parameters:
    ///   - statusCode: The HTTP status code
    ///   - logMessage: Optional custom log message
    /// - Returns: URLError with appropriate error code and user info
    static func fromHTTPStatusCode(_ statusCode: Int, logMessage: String? = nil) -> URLError {
        // Log the status code
        let message = logMessage ?? "HTTP Status Code: \(statusCode)"
        EdgenLogger.debug(message)
        
        // Map status codes to appropriate URLError codes
        let errorCode: URLError.Code
        switch statusCode {
        case 400:
            errorCode = .badURL
        case 401, 403:
            errorCode = .userAuthenticationRequired
        case 404:
            errorCode = .fileDoesNotExist
        case 408:
            errorCode = .timedOut
        case 500...599:
            errorCode = .badServerResponse
        case 300...399:
            errorCode = .redirectToNonExistentLocation
        default:
            errorCode = .badServerResponse
        }
        
        return URLError(
            errorCode,
            userInfo: [
                NSLocalizedDescriptionKey: "Server returned status code \(statusCode)",
                "statusCode": statusCode
            ]
        )
    }
}
