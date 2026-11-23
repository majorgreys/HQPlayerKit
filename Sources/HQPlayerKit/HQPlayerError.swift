import Foundation

public enum HQPlayerError: Error, Equatable {
    case notConnected
    case connectionFailed(String)
    case connectionClosed
    case sendFailed(String)
    case receiveFailed(String)
    case parseFailure(String)
    /// HQPlayer answered with `result="Error"`. The associated message is the
    /// element body (e.g. "Unknown command").
    case commandError(command: String, message: String)
    /// HQPlayer answered with a `result` other than "OK" or "Error" (or with
    /// no `result` at all). Captured for debuggability — shouldn't happen on
    /// the verified vocabulary.
    case unexpectedResult(command: String, result: String?)
    /// Preflight: queue is empty so Play / Next / Previous can't do anything.
    /// Surfaces before HQPlayer's engine 404s on the missing track URL.
    case queueEmpty
    /// Preflight: nothing currently loaded so Seek has no track to seek in.
    case noCurrentTrack
}

extension HQPlayerError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? {
        switch self {
        case .notConnected:                          return "HQPlayer client is not connected."
        case .connectionFailed(let m):               return "HQPlayer connect failed: \(m)"
        case .connectionClosed:                      return "HQPlayer connection closed."
        case .sendFailed(let m):                     return "HQPlayer send failed: \(m)"
        case .receiveFailed(let m):                  return "HQPlayer receive failed: \(m)"
        case .parseFailure(let m):                   return "HQPlayer response parse failed: \(m)"
        case .commandError(let cmd, let msg):        return "HQPlayer rejected \(cmd): \(msg)"
        case .unexpectedResult(let cmd, let result): return "HQPlayer returned unexpected result on \(cmd): \(result ?? "(nil)")"
        case .queueEmpty:                            return "Nothing in HQPlayer's queue."
        case .noCurrentTrack:                        return "No track currently loaded in HQPlayer."
        }
    }

    /// CustomStringConvertible so ArgumentParser's default error formatter
    /// (which uses `String(describing:)` not `localizedDescription`) prints
    /// the friendly text instead of the case name.
    public var description: String { errorDescription ?? "HQPlayer error" }
}
