import Foundation

public struct HQPlayerCommand: Sendable, Equatable {
    public let name: String
    public let attributes: [(key: String, value: String)]

    public init(name: String, attributes: [(key: String, value: String)] = []) {
        self.name = name
        self.attributes = attributes
    }

    public static func == (lhs: HQPlayerCommand, rhs: HQPlayerCommand) -> Bool {
        guard lhs.name == rhs.name, lhs.attributes.count == rhs.attributes.count else { return false }
        for (l, r) in zip(lhs.attributes, rhs.attributes) where l.key != r.key || l.value != r.value {
            return false
        }
        return true
    }
}

/// Parsed wire response: `<Cmd result="..." attrA="..." ...>body</Cmd>`.
/// `result` is hoisted out of the bag because every well-formed response
/// reports it; everything else stays in `attributes`. `body` is the text
/// payload (used for the human-readable error text on `result="Error"`).
public struct HQPlayerResponse: Sendable, Equatable {
    public let name: String
    public let result: String?
    public let attributes: [String: String]
    public let body: String
    public let children: [HQPlayerResponse]

    public init(
        name: String,
        result: String? = nil,
        attributes: [String: String] = [:],
        body: String = "",
        children: [HQPlayerResponse] = []
    ) {
        self.name = name
        self.result = result
        self.attributes = attributes
        self.body = body
        self.children = children
    }

    public var isOK: Bool { result == "OK" }
}

public enum HQPlayerCodec {
    /// Encode a command as bytes ready to send over the TCP socket. Always
    /// emits a self-closing tag (HQPlayer's command grammar has no body on
    /// the request side).
    public static func encode(_ command: HQPlayerCommand) -> Data {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><\(command.name)"
        for (key, value) in command.attributes {
            s += " \(key)=\"\(escapeAttribute(value))\""
        }
        s += "/>"
        return Data(s.utf8)
    }

    public static func parse(_ data: Data) throws -> HQPlayerResponse {
        let parser = XMLParser(data: data)
        let delegate = HQPlayerXMLDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = delegate.root else {
            throw HQPlayerError.parseFailure(parser.parserError?.localizedDescription ?? "no root element")
        }
        return root
    }

    static func escapeAttribute(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out.append("&amp;")
            case "\"": out.append("&quot;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            default: out.append(ch)
            }
        }
        return out
    }

    /// Returns true when `data` contains a complete top-level element. Used
    /// by the TCP read loop to know when a response has fully arrived without
    /// re-parsing on every byte.
    ///
    /// Tracks tag depth by scanning bytes: opens `<Foo`, closes `</Foo>` and
    /// self-closing `<Foo .../>` adjust depth. Comments, CDATA, processing
    /// instructions (`<?xml?>`), and DOCTYPE are skipped without affecting
    /// depth. The capture format only emits one root element, so as soon as
    /// depth returns to zero after rising we're done.
    public static func isCompleteElement(_ data: Data) -> Bool {
        var depth = 0
        var sawRoot = false
        var i = data.startIndex
        let end = data.endIndex
        while i < end {
            let b = data[i]
            if b == 0x3C { // '<'
                let next = data.index(after: i)
                if next >= end { return false }
                let n = data[next]
                if n == 0x21 { // '<!' — comment, CDATA, doctype
                    if let close = scanFindClose(data, from: next) {
                        i = data.index(after: close)
                        continue
                    } else {
                        return false
                    }
                } else if n == 0x3F { // '<?' processing instruction
                    if let close = scanFindPIClose(data, from: next) {
                        i = data.index(after: close)
                        continue
                    } else {
                        return false
                    }
                } else if n == 0x2F { // '</' close tag
                    if let close = scanFindClose(data, from: next) {
                        depth -= 1
                        i = data.index(after: close)
                        if sawRoot && depth == 0 { return true }
                        continue
                    } else {
                        return false
                    }
                } else { // '<Tag ...' open or self-closing
                    guard let close = scanFindTagClose(data, from: next) else { return false }
                    if data[close] == 0x2F { // self-closing if char before '>' is '/'
                        // already self-closing tag — depth net zero
                        if !sawRoot { sawRoot = true; if depth == 0 { return true } }
                        i = data.index(after: data.index(after: close))
                        continue
                    }
                    if close > data.startIndex && data[data.index(before: close)] == 0x2F {
                        if !sawRoot { sawRoot = true; if depth == 0 { return true } }
                        i = data.index(after: close)
                        continue
                    }
                    depth += 1
                    sawRoot = true
                    i = data.index(after: close)
                    continue
                }
            }
            i = data.index(after: i)
        }
        return sawRoot && depth == 0
    }

    private static func scanFindClose(_ data: Data, from start: Data.Index) -> Data.Index? {
        var i = start
        while i < data.endIndex {
            if data[i] == 0x3E { return i } // '>'
            i = data.index(after: i)
        }
        return nil
    }

    private static func scanFindPIClose(_ data: Data, from start: Data.Index) -> Data.Index? {
        var i = start
        while i < data.endIndex {
            if data[i] == 0x3F { // '?'
                let n = data.index(after: i)
                if n < data.endIndex && data[n] == 0x3E { return n }
            }
            i = data.index(after: i)
        }
        return nil
    }

    /// Find the closing `>` of a tag. Naive but correct for HQPlayer's
    /// attribute grammar (double-quoted values, no `>` inside attribute
    /// values in any observed response).
    private static func scanFindTagClose(_ data: Data, from start: Data.Index) -> Data.Index? {
        var i = start
        var inQuote = false
        while i < data.endIndex {
            let b = data[i]
            if b == 0x22 { inQuote.toggle() } // '"'
            else if b == 0x3E && !inQuote { return i } // '>'
            i = data.index(after: i)
        }
        return nil
    }
}

private final class HQPlayerXMLDelegate: NSObject, XMLParserDelegate {
    var root: HQPlayerResponse?
    private var stack: [(name: String, attrs: [String: String], body: String, children: [HQPlayerResponse])] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        stack.append((name: elementName, attrs: attributeDict, body: "", children: []))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].body += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let top = stack.popLast() else { return }
        var attrs = top.attrs
        let result = attrs.removeValue(forKey: "result")
        let trimmed = top.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = HQPlayerResponse(
            name: top.name,
            result: result,
            attributes: attrs,
            body: trimmed,
            children: top.children
        )
        if stack.isEmpty {
            root = node
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }
}
