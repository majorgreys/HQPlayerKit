import Foundation

/// Indirection between high-level methods (`setFilter`, `applyProfile`, …)
/// and the actual transport. Lets tests inject a recording fake without
/// standing up a TCP server.
public protocol HQPlayerCommandSink: Sendable {
    func send(_ command: HQPlayerCommand) async throws -> HQPlayerResponse
}
