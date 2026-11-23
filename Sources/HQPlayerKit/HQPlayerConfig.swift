import Foundation
import os

private var log: Logger { HQPlayerKitLog.logger("hqplayer-config") }

/// Persistent HQPlayer configuration: a hand-editable JSON file whose location
/// the caller chooses.
public struct HQPlayerConfig: Codable, Sendable, Equatable {
    public var host: String
    public var port: Int?
    public var profiles: [HQPlayerProfile]

    public init(host: String, port: Int? = nil, profiles: [HQPlayerProfile] = []) {
        self.host = host
        self.port = port
        self.profiles = profiles
    }

    /// Empty-but-valid default. `host` is intentionally blank so callers know
    /// to prompt — saving this as-is would let `HQPlayerClient` attempt a
    /// connection to an empty hostname and fail loudly, which is what we want.
    public static let `default` = HQPlayerConfig(host: "", port: nil, profiles: [])

    public static func load(from path: URL) -> HQPlayerConfig? {
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch let err as CocoaError where err.code == .fileReadNoSuchFile {
            return nil
        } catch let err as NSError where err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            log.error("hqplayer config read failed at \(path.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        do {
            return try JSONDecoder().decode(HQPlayerConfig.self, from: data)
        } catch {
            log.error("hqplayer config JSON decode failed at \(path.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func save(to path: URL) throws {
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: path, options: .atomic)
    }

    public func profile(named name: String) -> HQPlayerProfile? {
        profiles.first { $0.name == name }
    }
}
