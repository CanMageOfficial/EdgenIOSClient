// Logger.swift
// Shared static logging utility

import Foundation
import OSLog

final class EdgenLogger {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.canmage.edgen", category: "EdgenLogger")
    
    static func info(_ message: String) {
        logger.info("\(message)")
    }
    
    static func error(_ message: String) {
        logger.error("\(message)")
    }
    
    static func debug(_ message: String) {
        logger.debug("\(message)")
    }
    
    static func warning(_ message: String) {
        logger.warning("\(message)")
    }
}
