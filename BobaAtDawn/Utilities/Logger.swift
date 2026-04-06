//
//  Logger.swift
//  BobaAtDawn
//
//  Centralized logging with per-category filtering
//

import Foundation

// MARK: - Log Level
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case none = 4
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var tag: String {
        switch self {
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .warning: return "⚠️ WARN"
        case .error:   return "❌ ERROR"
        case .none:    return ""
        }
    }
}

// MARK: - Log Category
enum LogCategory: String {
    case game      = "🎮"
    case npc       = "🦊"
    case grid      = "🎯"
    case physics   = "⚡"
    case time      = "🌅"
    case ritual    = "🕯️"
    case save      = "💾"
    case dialogue  = "💬"
    case animation = "🎭"
    case scene     = "🌍"
    case input     = "👆"
    case drink     = "🧋"
    case forest    = "🌲"
    case resident  = "🏘️"
}

// MARK: - Logger
final class Log {
    
    static let shared = Log()
    
    #if DEBUG
    var globalLevel: LogLevel = .debug
    #else
    var globalLevel: LogLevel = .warning
    #endif
    
    private var categoryLevels: [LogCategory: LogLevel] = [:]
    
    private init() {}
    
    // MARK: - Category Filtering
    
    /// Override the log level for a specific category.
    func setLevel(_ level: LogLevel, for category: LogCategory) {
        categoryLevels[category] = level
    }
    
    /// Silence a category entirely.
    func mute(_ category: LogCategory) {
        categoryLevels[category] = .none
    }
    
    func effectiveLevel(for category: LogCategory) -> LogLevel {
        categoryLevels[category] ?? globalLevel
    }
    
    // MARK: - Core
    
    func log(_ level: LogLevel, _ category: LogCategory,
             _ message: @autoclosure () -> String,
             file: String = #file, line: Int = #line) {
        guard level >= effectiveLevel(for: category) else { return }
        let fileName = (file as NSString).lastPathComponent
        print("\(category.rawValue) [\(level.tag)] \(message()) (\(fileName):\(line))")
    }
    
    // MARK: - Convenience
    
    static func debug(_ cat: LogCategory, _ msg: @autoclosure () -> String,
                      file: String = #file, line: Int = #line) {
        shared.log(.debug, cat, msg(), file: file, line: line)
    }
    
    static func info(_ cat: LogCategory, _ msg: @autoclosure () -> String,
                     file: String = #file, line: Int = #line) {
        shared.log(.info, cat, msg(), file: file, line: line)
    }
    
    static func warn(_ cat: LogCategory, _ msg: @autoclosure () -> String,
                     file: String = #file, line: Int = #line) {
        shared.log(.warning, cat, msg(), file: file, line: line)
    }
    
    static func error(_ cat: LogCategory, _ msg: @autoclosure () -> String,
                      file: String = #file, line: Int = #line) {
        shared.log(.error, cat, msg(), file: file, line: line)
    }
}
