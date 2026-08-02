import os

// Structured logging — visible in Console.app and sysdiagnose, unlike print().
enum AppLog {
    static let analysis = Logger(subsystem: "com.arnavkewalram.SwimCoach", category: "analysis")
    static let model    = Logger(subsystem: "com.arnavkewalram.SwimCoach", category: "model")
    static let storage  = Logger(subsystem: "com.arnavkewalram.SwimCoach", category: "storage")
    static let camera   = Logger(subsystem: "com.arnavkewalram.SwimCoach", category: "camera")
}
