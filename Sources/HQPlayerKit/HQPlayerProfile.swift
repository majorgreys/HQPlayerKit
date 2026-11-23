import Foundation

/// A named bundle of HQPlayer DSP settings. HQPlayer 5 has no native
/// profile-switching primitive (see research doc), so a profile is just a
/// recipe of `<SetFilter/>`, `<SetShaping/>`, `<SetMode/>`, `<SetRate/>`,
/// `<Volume/>` mutations replayed in sequence.
public struct HQPlayerProfile: Codable, Sendable, Equatable {
    public var name: String
    public var filter: String?
    public var shaping: String?
    public var mode: String?
    public var rate: Int?
    public var volumeLimit: Double?

    public init(
        name: String,
        filter: String? = nil,
        shaping: String? = nil,
        mode: String? = nil,
        rate: Int? = nil,
        volumeLimit: Double? = nil
    ) {
        self.name = name
        self.filter = filter
        self.shaping = shaping
        self.mode = mode
        self.rate = rate
        self.volumeLimit = volumeLimit
    }
}

/// Top-level method that drives an arbitrary `HQPlayerCommandSink`. Mirrors
/// `HQPlayerClient.applyProfile(_:)` so tests can exercise the same logic
/// against a recording fake without spinning up a TCP server.
public func applyProfile(_ profile: HQPlayerProfile, to sink: HQPlayerCommandSink) async throws {
    if let mode = profile.mode {
        _ = try await sink.send(HQPlayerCommand(name: "SetMode", attributes: [("value", mode)]))
    }
    if let rate = profile.rate {
        _ = try await sink.send(HQPlayerCommand(name: "SetRate", attributes: [("value", String(rate))]))
    }
    if let filter = profile.filter {
        _ = try await sink.send(HQPlayerCommand(name: "SetFilter", attributes: [("value", filter)]))
    }
    if let shaping = profile.shaping {
        _ = try await sink.send(HQPlayerCommand(name: "SetShaping", attributes: [("value", shaping)]))
    }
    if let db = profile.volumeLimit {
        let formatted = db.rounded() == db ? String(Int(db)) : String(format: "%g", db)
        _ = try await sink.send(HQPlayerCommand(name: "Volume", attributes: [("value", formatted)]))
    }
}
