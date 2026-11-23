import XCTest
@testable import HQPlayerKit

final class XMLCodecTests: XCTestCase {
    func test_encodesEmptyCommandAsSelfClosingTag() {
        let cmd = HQPlayerCommand(name: "Status")
        let bytes = HQPlayerCodec.encode(cmd)
        let s = String(data: bytes, encoding: .utf8)!
        XCTAssertEqual(s, "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Status/>")
    }

    func test_encodesAttributesInDeclaredOrder() {
        let cmd = HQPlayerCommand(name: "Seek", attributes: [("position", "42")])
        let s = String(data: HQPlayerCodec.encode(cmd), encoding: .utf8)!
        XCTAssertEqual(s, "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Seek position=\"42\"/>")
    }

    func test_escapesAttributeValueSpecials() {
        let cmd = HQPlayerCommand(name: "SetFilter", attributes: [
            ("value", "a&b\"c<d>e"),
        ])
        let s = String(data: HQPlayerCodec.encode(cmd), encoding: .utf8)!
        XCTAssertEqual(s, "<?xml version=\"1.0\" encoding=\"UTF-8\"?><SetFilter value=\"a&amp;b&quot;c&lt;d&gt;e\"/>")
    }

    func test_parsesCapturedStatusReply() throws {
        // Lifted verbatim from a captured HQPlayer status reply.
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>\
        <Status active_bits="1" active_channels="2" \
        active_filter="poly-sinc-gauss-long" \
        active_mode="SDM (DSD)" \
        active_rate="44100" \
        active_shaper="ASDM7EC-light 512+fs" \
        apod="0" begin_min="0" begin_sec="0" clips="0" correction="0" \
        display_position="0" filter_20k="1" input_fill="0" \
        length="0" min="0" output_delay="0" output_fill="0" \
        position="0" process_speed="0" queued="0" random="0" \
        remain_min="0" remain_sec="0" sec="0" state="0"/>
        """
        let r = try HQPlayerCodec.parse(Data(xml.utf8))
        XCTAssertEqual(r.name, "Status")
        XCTAssertNil(r.result, "captured fixture has no result attribute (live capture omits it)")
        XCTAssertEqual(r.attributes["active_filter"], "poly-sinc-gauss-long")
        XCTAssertEqual(r.attributes["active_shaper"], "ASDM7EC-light 512+fs")
        XCTAssertEqual(r.attributes["active_mode"], "SDM (DSD)")
        XCTAssertEqual(r.attributes["active_rate"], "44100")
        XCTAssertEqual(r.attributes["active_bits"], "1")
        XCTAssertEqual(r.attributes["active_channels"], "2")
        XCTAssertEqual(r.attributes["state"], "0")

        let typed = HQPlayerStatus.from(attributes: r.attributes)
        XCTAssertEqual(typed.activeFilter, "poly-sinc-gauss-long")
        XCTAssertEqual(typed.activeRate, 44100)
        XCTAssertEqual(typed.activeChannels, 2)
        XCTAssertEqual(typed.state, 0)
    }

    func test_parsesOKResponseWithResultAttribute() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><SetFilter result=\"OK\" value=\"38\"/>"
        let r = try HQPlayerCodec.parse(Data(xml.utf8))
        XCTAssertEqual(r.name, "SetFilter")
        XCTAssertEqual(r.result, "OK")
        XCTAssertTrue(r.isOK)
        XCTAssertEqual(r.attributes["value"], "38")
    }

    func test_parsesErrorResponseWithBody() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><Bogus result=\"Error\">Unknown command</Bogus>"
        let r = try HQPlayerCodec.parse(Data(xml.utf8))
        XCTAssertEqual(r.name, "Bogus")
        XCTAssertEqual(r.result, "Error")
        XCTAssertFalse(r.isOK)
        XCTAssertEqual(r.body, "Unknown command")
    }

    func test_isCompleteElementHandlesSelfClosingRoot() {
        let xml = Data("<?xml version=\"1.0\"?><Status/>".utf8)
        XCTAssertTrue(HQPlayerCodec.isCompleteElement(xml))
    }

    func test_isCompleteElementHandlesOpenCloseRoot() {
        let xml = Data("<?xml version=\"1.0\"?><GetFilters><Filter index=\"1\"/><Filter index=\"2\"/></GetFilters>".utf8)
        XCTAssertTrue(HQPlayerCodec.isCompleteElement(xml))
    }

    func test_isCompleteElementRejectsTruncated() {
        let truncated = Data("<?xml version=\"1.0\"?><GetFilters><Filter index=\"1".utf8)
        XCTAssertFalse(HQPlayerCodec.isCompleteElement(truncated))
        let truncatedClose = Data("<?xml version=\"1.0\"?><GetFilters><Filter index=\"1\"/>".utf8)
        XCTAssertFalse(HQPlayerCodec.isCompleteElement(truncatedClose))
    }

    func test_roundtripPreservesAttributesAfterEscaping() throws {
        let cmd = HQPlayerCommand(name: "SetMode", attributes: [
            ("value", "SDM \"DSD\" & PCM"),
        ])
        let bytes = HQPlayerCodec.encode(cmd)
        let parsed = try HQPlayerCodec.parse(bytes)
        XCTAssertEqual(parsed.name, "SetMode")
        XCTAssertEqual(parsed.attributes["value"], "SDM \"DSD\" & PCM")
    }
}
