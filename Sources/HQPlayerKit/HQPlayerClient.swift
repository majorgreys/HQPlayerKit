import Foundation
import Network

/// XML-over-TCP client for HQPlayer Embedded / Desktop on port 4321.
///
/// One actor owns one `NWConnection`. Single in-flight request at a time;
/// concurrent callers serialize naturally on the actor. On any transport
/// failure the client transitions to a terminal disconnected state and all
/// subsequent calls throw — the research doc explicitly scopes reconnect
/// out, leaving it to the caller.
public actor HQPlayerClient: HQPlayerCommandSink {
    public static let defaultPort: Int = 4321

    public let host: String
    public let port: Int

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    /// Connection-failure latch. Once set (a `.failed`/`.cancelled` state on
    /// the NWConnection or any I/O error) every subsequent call throws this
    /// without touching the socket. `connect()` is the only thing that clears it.
    private var fatalError: HQPlayerError?

    public init(host: String, port: Int = HQPlayerClient.defaultPort) {
        self.host = host
        self.port = port
    }

    public func connect() async throws {
        if connection != nil { return }
        let endpointPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        let endpointHost = NWEndpoint.Host(host)
        let conn = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        connection = conn
        receiveBuffer.removeAll(keepingCapacity: true)
        fatalError = nil

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume() }
                case .failed(let err):
                    if !resumed {
                        resumed = true
                        cont.resume(throwing: HQPlayerError.connectionFailed(err.localizedDescription))
                    }
                    Task { await self?.handleFailure(.connectionFailed(err.localizedDescription)) }
                case .cancelled:
                    Task { await self?.handleFailure(.connectionClosed) }
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        fatalError = .connectionClosed
    }

    public func send(_ command: HQPlayerCommand) async throws -> HQPlayerResponse {
        if let fatalError { throw fatalError }
        guard let conn = connection else { throw HQPlayerError.notConnected }
        let payload = HQPlayerCodec.encode(command)
        try await sendBytes(conn: conn, data: payload)
        let responseBytes = try await readUntilElementClose(conn: conn)
        let response = try HQPlayerCodec.parse(responseBytes)
        if let result = response.result, result != "OK" {
            if result == "Error" {
                throw HQPlayerError.commandError(command: command.name, message: response.body)
            }
            throw HQPlayerError.unexpectedResult(command: command.name, result: result)
        }
        return response
    }

    // MARK: - High-level commands

    public func getInfo() async throws -> HQPlayerInfo {
        let r = try await send(HQPlayerCommand(name: "GetInfo"))
        return HQPlayerInfo(
            engine: r.attributes["engine"] ?? "",
            name: r.attributes["name"] ?? "",
            platform: r.attributes["platform"] ?? "",
            product: r.attributes["product"] ?? "",
            version: r.attributes["version"] ?? ""
        )
    }

    public func status() async throws -> HQPlayerStatus {
        let r = try await send(HQPlayerCommand(name: "Status"))
        return HQPlayerStatus.from(attributes: r.attributes)
    }

    public func getFilters() async throws -> [HQPlayerFilter] {
        let r = try await send(HQPlayerCommand(name: "GetFilters"))
        return r.children.map { child in
            HQPlayerFilter(
                index: child.attributes["index"] ?? "",
                name: child.attributes["name"] ?? child.body,
                value: child.attributes["value"] ?? child.attributes["index"] ?? ""
            )
        }
    }

    public func getShapers() async throws -> [HQPlayerShaper] {
        let r = try await send(HQPlayerCommand(name: "GetShapers"))
        return r.children.map { child in
            HQPlayerShaper(
                index: child.attributes["index"] ?? "",
                name: child.attributes["name"] ?? child.body,
                value: child.attributes["value"] ?? child.attributes["index"] ?? ""
            )
        }
    }

    public func getRates() async throws -> [Int] {
        let r = try await send(HQPlayerCommand(name: "GetRates"))
        return r.children.compactMap { child in
            Int(child.attributes["value"] ?? child.attributes["rate"] ?? child.body)
        }
    }

    public func getModes() async throws -> [String] {
        let r = try await send(HQPlayerCommand(name: "GetModes"))
        return r.children.map { child in
            child.attributes["value"] ?? child.attributes["name"] ?? child.body
        }
    }

    public func setFilter(value: String) async throws {
        _ = try await send(HQPlayerCommand(name: "SetFilter", attributes: [("value", value)]))
    }

    public func setShaping(value: String) async throws {
        _ = try await send(HQPlayerCommand(name: "SetShaping", attributes: [("value", value)]))
    }

    public func setRate(value: Int) async throws {
        _ = try await send(HQPlayerCommand(name: "SetRate", attributes: [("value", String(value))]))
    }

    public func setMode(value: String) async throws {
        _ = try await send(HQPlayerCommand(name: "SetMode", attributes: [("value", value)]))
    }

    public func volume(db: Double) async throws {
        let formatted = formatVolumeDB(db)
        _ = try await send(HQPlayerCommand(name: "Volume", attributes: [("value", formatted)]))
    }

    public func volumeUp() async throws {
        _ = try await send(HQPlayerCommand(name: "VolumeUp"))
    }

    public func volumeDown() async throws {
        _ = try await send(HQPlayerCommand(name: "VolumeDown"))
    }

    public func play() async throws {
        try await preflightQueueNonEmpty()
        _ = try await send(HQPlayerCommand(name: "Play"))
    }

    public func pause() async throws {
        _ = try await send(HQPlayerCommand(name: "Pause"))
    }

    public func stop() async throws {
        _ = try await send(HQPlayerCommand(name: "Stop"))
    }

    public func next() async throws {
        try await preflightQueueNonEmpty()
        _ = try await send(HQPlayerCommand(name: "Next"))
    }

    public func previous() async throws {
        try await preflightQueueNonEmpty()
        _ = try await send(HQPlayerCommand(name: "Previous"))
    }

    public func seek(seconds: Int) async throws {
        let s = try await status()
        guard (s.length ?? 0) > 0 else { throw HQPlayerError.noCurrentTrack }
        _ = try await send(HQPlayerCommand(name: "Seek", attributes: [("position", String(seconds))]))
    }

    /// Preflight transport mutations against `<Status/>` — without this the
    /// engine returns a confusing `clHQPlayerEngine::Play(): ... GetHead(): 404`
    /// when the queue is empty. Costs one extra Status request per Play /
    /// Next / Previous (HQPlayer responds in ~2-5ms).
    private func preflightQueueNonEmpty() async throws {
        let s = try await status()
        guard s.tracksTotal > 0 else { throw HQPlayerError.queueEmpty }
    }

    public func applyProfile(_ profile: HQPlayerProfile) async throws {
        try await HQPlayerKit.applyProfile(profile, to: self)
    }

    // MARK: - Internals

    private func handleFailure(_ error: HQPlayerError) {
        fatalError = error
        connection = nil
    }

    private func sendBytes(conn: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err {
                    cont.resume(throwing: HQPlayerError.sendFailed(err.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    /// Drain the socket until `receiveBuffer` contains a complete root
    /// element, then return that element's bytes (leaving any trailing bytes
    /// — there shouldn't be any in v1 — for the next call).
    private func readUntilElementClose(conn: NWConnection) async throws -> Data {
        while !HQPlayerCodec.isCompleteElement(receiveBuffer) {
            let chunk = try await receiveOnce(conn: conn)
            if chunk.isEmpty { throw HQPlayerError.connectionClosed }
            receiveBuffer.append(chunk)
        }
        let out = receiveBuffer
        receiveBuffer.removeAll(keepingCapacity: true)
        return out
    }

    private func receiveOnce(conn: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { content, _, isComplete, err in
                if let err {
                    cont.resume(throwing: HQPlayerError.receiveFailed(err.localizedDescription))
                    return
                }
                if let content, !content.isEmpty {
                    cont.resume(returning: content)
                    return
                }
                if isComplete {
                    cont.resume(throwing: HQPlayerError.connectionClosed)
                    return
                }
                cont.resume(returning: Data())
            }
        }
    }

    /// Format dB without trailing-zero noise. HQPlayer accepts integer or
    /// decimal strings; we emit `-30` for whole numbers and `-30.5` for
    /// fractional, matching the wire examples in the research doc.
    private func formatVolumeDB(_ db: Double) -> String {
        if db.rounded() == db {
            return String(Int(db))
        }
        return String(format: "%g", db)
    }
}
