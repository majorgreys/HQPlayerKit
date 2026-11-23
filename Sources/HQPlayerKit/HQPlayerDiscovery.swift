import Foundation
import Darwin

public struct DiscoveredHQPlayer: Sendable, Equatable {
    public let host: String
    public let name: String

    public init(host: String, name: String) {
        self.host = host
        self.name = name
    }
}

/// UDP discovery for HQPlayer instances on the LAN.
///
/// **Caveat:** the research doc names a `<discover>hqplayer</discover>` probe
/// on port 4321 but doesn't pin down the multicast group address (or whether
/// HQPlayer answers broadcast). This implementation broadcasts to
/// `255.255.255.255:4321` — the lowest-friction probe that should work on a
/// flat home LAN — and parses replies as either a literal hostname/name pair
/// or as an XML reply containing `name="..."`. If no replies arrive, the
/// caller gets an empty array; that's the signal to fall back to a configured
/// host. Tracked as a follow-up (the wire details for HQPlayer's discovery
/// reply format are not in the research doc).
public enum HQPlayerDiscovery {
    public static func discover(timeout: TimeInterval = 2, port: Int = 4321) async -> [DiscoveredHQPlayer] {
        let probe = Data("<discover>hqplayer</discover>".utf8)
        return await Task.detached(priority: .userInitiated) {
            broadcastDiscover(probe: probe, timeout: timeout, port: UInt16(port))
        }.value
    }

    private static func broadcastDiscover(probe: Data, timeout: TimeInterval, port: UInt16) -> [DiscoveredHQPlayer] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
        bindAddr.sin_port = 0
        let bindResult = withUnsafePointer(to: &bindAddr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return [] }

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian
        dest.sin_addr.s_addr = UInt32(0xFFFF_FFFF)
        let sent = probe.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> ssize_t in
            withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == probe.count else { return [] }

        let deadline = Date().addingTimeInterval(timeout)
        var collected: [String: DiscoveredHQPlayer] = [:]
        var rcvBuf = [UInt8](repeating: 0, count: 4096)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while Date() < deadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            var tv = timeval(
                tv_sec: time_t(remaining),
                tv_usec: __darwin_suseconds_t((remaining - floor(remaining)) * 1_000_000)
            )
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            let n = rcvBuf.withUnsafeMutableBufferPointer { (buf: inout UnsafeMutableBufferPointer<UInt8>) -> ssize_t in
                withUnsafeMutablePointer(to: &srcAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, buf.baseAddress, buf.count, 0, sa, &srcLen)
                    }
                }
            }
            guard n > 0 else { continue }

            let payload = Data(bytes: rcvBuf, count: n)
            let host = ipv4String(srcAddr.sin_addr)
            let name = parseDiscoveryName(payload) ?? host
            collected[host] = DiscoveredHQPlayer(host: host, name: name)
        }

        return Array(collected.values)
    }

    /// Best-effort name extraction. Tries XML `name="..."` attribute first
    /// (matches the `<GetInfo .../>` reply shape, which HQPlayer might also
    /// use for discovery), then falls back to the raw payload trimmed.
    private static func parseDiscoveryName(_ data: Data) -> String? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        if let range = s.range(of: "name=\"") {
            let after = s[range.upperBound...]
            if let end = after.firstIndex(of: "\"") {
                return String(after[..<end])
            }
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func ipv4String(_ addr: in_addr) -> String {
        let raw = addr.s_addr
        let bytes = withUnsafeBytes(of: raw) { Array($0) }
        return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
    }
}
