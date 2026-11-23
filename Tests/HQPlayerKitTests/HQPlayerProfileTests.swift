import XCTest
@testable import HQPlayerKit

/// Records every command sent through it. Lets the profile-application tests
/// verify the exact wire vocabulary without needing a TCP server.
actor RecordingSink: HQPlayerCommandSink {
    private(set) var sent: [HQPlayerCommand] = []

    func send(_ command: HQPlayerCommand) async throws -> HQPlayerResponse {
        sent.append(command)
        return HQPlayerResponse(name: command.name, result: "OK")
    }

    func snapshot() -> [HQPlayerCommand] { sent }
}

actor FailingSink: HQPlayerCommandSink {
    let failOn: String
    private(set) var sent: [HQPlayerCommand] = []

    init(failOn: String) { self.failOn = failOn }

    func send(_ command: HQPlayerCommand) async throws -> HQPlayerResponse {
        sent.append(command)
        if command.name == failOn {
            throw HQPlayerError.commandError(command: command.name, message: "boom")
        }
        return HQPlayerResponse(name: command.name, result: "OK")
    }

    func snapshot() -> [HQPlayerCommand] { sent }
}

final class HQPlayerProfileTests: XCTestCase {
    func test_appliesPartialProfile_skippingNilFields() async throws {
        let profile = HQPlayerProfile(
            name: "headphone",
            filter: "38",
            shaping: nil,
            mode: "SDM",
            rate: nil,
            volumeLimit: -3
        )
        let sink = RecordingSink()
        try await applyProfile(profile, to: sink)

        let issued = await sink.snapshot()
        XCTAssertEqual(issued.count, 3)
        XCTAssertEqual(issued[0], HQPlayerCommand(name: "SetMode", attributes: [("value", "SDM")]))
        XCTAssertEqual(issued[1], HQPlayerCommand(name: "SetFilter", attributes: [("value", "38")]))
        XCTAssertEqual(issued[2], HQPlayerCommand(name: "Volume", attributes: [("value", "-3")]))
    }

    func test_emitsAllSettersWhenAllFieldsPresent() async throws {
        let profile = HQPlayerProfile(
            name: "all",
            filter: "40",
            shaping: "23",
            mode: "PCM",
            rate: 1_536_000,
            volumeLimit: -10
        )
        let sink = RecordingSink()
        try await applyProfile(profile, to: sink)

        let issued = await sink.snapshot().map(\.name)
        XCTAssertEqual(issued, ["SetMode", "SetRate", "SetFilter", "SetShaping", "Volume"])
    }

    func test_skipsEverythingWhenAllFieldsNil() async throws {
        let profile = HQPlayerProfile(name: "noop")
        let sink = RecordingSink()
        try await applyProfile(profile, to: sink)
        let issued = await sink.snapshot()
        XCTAssertTrue(issued.isEmpty)
    }

    func test_throwsAndStopsOnFirstFailure() async {
        let profile = HQPlayerProfile(
            name: "failmid",
            filter: "38",
            shaping: "22",
            mode: "SDM",
            rate: 11_289_600,
            volumeLimit: -3
        )
        let sink = FailingSink(failOn: "SetFilter")
        do {
            try await applyProfile(profile, to: sink)
            XCTFail("expected throw")
        } catch let HQPlayerError.commandError(command, _) {
            XCTAssertEqual(command, "SetFilter")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
        let issued = await sink.snapshot().map(\.name)
        XCTAssertEqual(issued, ["SetMode", "SetRate", "SetFilter"], "stops at the failing command, doesn't continue")
    }

    func test_configRoundtripsThroughJSON() throws {
        let cfg = HQPlayerConfig(
            host: "192.0.2.10",
            port: 4321,
            profiles: [
                HQPlayerProfile(name: "headphone", filter: "38", shaping: "22", mode: "SDM", rate: 11_289_600, volumeLimit: -3),
                HQPlayerProfile(name: "2-channel", filter: "40", mode: "PCM", rate: 1_536_000),
            ]
        )
        let encoded = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(HQPlayerConfig.self, from: encoded)
        XCTAssertEqual(decoded, cfg)
        XCTAssertEqual(decoded.profile(named: "headphone")?.filter, "38")
        XCTAssertNil(decoded.profile(named: "missing"))
    }
}
