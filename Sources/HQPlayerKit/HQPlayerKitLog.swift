import os

/// Unified-logging subsystem for HQPlayerKit's `os.Logger`s. Defaults to
/// `"HQPlayerKit"`; a host app sets its own subsystem once at startup, before
/// using HQPlayerKit. Loggers are built on each use, so the assignment applies
/// everywhere.
public enum HQPlayerKitLog {
    nonisolated(unsafe) public static var subsystem = "HQPlayerKit"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
