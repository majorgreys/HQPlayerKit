import Foundation

public struct HQPlayerInfo: Sendable, Equatable {
    public let engine: String
    public let name: String
    public let platform: String
    public let product: String
    public let version: String

    public init(engine: String, name: String, platform: String, product: String, version: String) {
        self.engine = engine
        self.name = name
        self.platform = platform
        self.product = product
        self.version = version
    }
}

/// Snapshot of HQPlayer's live state. Every attribute observed in
/// a live wire capture is surfaced; absent attributes decode as nil rather than zero so
/// callers can tell "not reported" from "explicitly zero".
public struct HQPlayerStatus: Sendable, Equatable {
    public let activeFilter: String?
    public let activeShaper: String?
    public let activeMode: String?
    public let activeRate: Int?
    public let activeBits: Int?
    public let activeChannels: Int?
    public let state: Int?
    public let position: Int?
    public let length: Int?
    public let volume: Double?

    /// Raw attribute bag — every attr reported by `<Status/>`, including ones
    /// not modeled above (apod, begin_min, clips, queued, …). Lets callers
    /// inspect anything the typed view drops.
    public let attributes: [String: String]

    public init(
        activeFilter: String? = nil,
        activeShaper: String? = nil,
        activeMode: String? = nil,
        activeRate: Int? = nil,
        activeBits: Int? = nil,
        activeChannels: Int? = nil,
        state: Int? = nil,
        position: Int? = nil,
        length: Int? = nil,
        volume: Double? = nil,
        attributes: [String: String] = [:]
    ) {
        self.activeFilter = activeFilter
        self.activeShaper = activeShaper
        self.activeMode = activeMode
        self.activeRate = activeRate
        self.activeBits = activeBits
        self.activeChannels = activeChannels
        self.state = state
        self.position = position
        self.length = length
        self.volume = volume
        self.attributes = attributes
    }

    public static func from(attributes: [String: String]) -> HQPlayerStatus {
        HQPlayerStatus(
            activeFilter: attributes["active_filter"],
            activeShaper: attributes["active_shaper"],
            activeMode: attributes["active_mode"],
            activeRate: attributes["active_rate"].flatMap(Int.init),
            activeBits: attributes["active_bits"].flatMap(Int.init),
            activeChannels: attributes["active_channels"].flatMap(Int.init),
            state: attributes["state"].flatMap(Int.init),
            position: attributes["position"].flatMap(Int.init),
            length: attributes["length"].flatMap(Int.init),
            volume: attributes["volume"].flatMap(Double.init),
            attributes: attributes
        )
    }

    /// Number of tracks currently in HQPlayer's queue. Read from the raw
    /// `tracks_total` attribute since `<Status/>` doesn't model it as a
    /// first-class field. Returns 0 when absent or unparseable.
    public var tracksTotal: Int { attributes["tracks_total"].flatMap(Int.init) ?? 0 }
}

/// One entry from `<GetFilters/>`. The `value` is what `<SetFilter value="..."/>`
/// expects — usually the same string as `index` but kept distinct because the
/// wire shape exposes them as separate attributes.
public struct HQPlayerFilter: Sendable, Equatable {
    public let index: String
    public let name: String
    public let value: String

    public init(index: String, name: String, value: String) {
        self.index = index
        self.name = name
        self.value = value
    }
}

public struct HQPlayerShaper: Sendable, Equatable {
    public let index: String
    public let name: String
    public let value: String

    public init(index: String, name: String, value: String) {
        self.index = index
        self.name = name
        self.value = value
    }
}
