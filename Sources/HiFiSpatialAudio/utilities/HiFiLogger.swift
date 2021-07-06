//
//  HifiLogger.swift
//  
//
//  Created by zach on 3/5/21.
//

import Foundation

/**
    Used for determining what data the High Fidelity Audio Client API should print to the logs.
*/
public enum HiFiLogLevel : String {
    case none = "None"
    case error = "Error"
    case warn = "Warn"
    case debug = "Debug"
}

/**
    A wrapper for `print()` calls, gated by the user's current log level.
*/
public class HiFiLogger {
    public static var logLevel: HiFiLogLevel = HiFiLogLevel.error

    /**
        Sets a new HiFi Log Level.
        - Parameter newLogLevel: The new Log Level for our Logger.
    */
    public static func setHiFiLogLevel(newLogLevel: HiFiLogLevel) -> Void {
        self.logLevel = newLogLevel
    }

    /**
        If the Logger's log level is `Debug`, will print a debug log to the logs.
        - Parameter message: The message to log.
        - Returns: `true` if the message was output to the logs; `false` otherwise.
    */
    @discardableResult public static func log(_ message: String) -> Bool {
        if (self.logLevel == HiFiLogLevel.debug) {
            print("Log: \(message)")
            return true
        } else {
            return false
        }
    }

    /**
        Does the same thing as `HiFiLogger.log`.
        - Parameter message: The message to log.
        - Returns `true` if the message was output to the logs; `false` otherwise.
    */
    @discardableResult public static func debug(_ message: String) -> Bool {
        if (self.logLevel == HiFiLogLevel.debug) {
            print("Log: \(message)")
            return true
        } else {
            return false
        }
    }

    /**
        If the Logger's log level is `Debug` or `Warn`, will print a warning log to the logs.
        - Parameter message - The message to log.
        - Returns: `true` if the message was output to the logs; `false` otherwise.
    */
    @discardableResult public static func warn(_ message: String) -> Bool {
        if (self.logLevel == HiFiLogLevel.debug || self.logLevel == HiFiLogLevel.warn) {
            print("Warning: \(message)")
            return true
        } else {
            return false
        }
    }

    /**
        If the Logger's log level is `Debug` or `Warn` or `Error`, will print an error log to the logs.
        - Parameter message: The message to log.
        - Returns: `true` if the message was output to the logs; `false` otherwise.
    */
    @discardableResult public static func error(_ message: String) -> Bool {
        if (self.logLevel == HiFiLogLevel.debug || self.logLevel == HiFiLogLevel.warn || self.logLevel == HiFiLogLevel.error) {
            print("Error: \(message)")
            return true
        } else {
            return false
        }
    }
}

