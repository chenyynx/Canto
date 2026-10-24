#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 

 
struct HTTP2HeaderBlock: Equatable, Sendable {
    var stream: UInt32
    var fields: [HPACKField]
     
    var endStream: Bool
    var priority: HTTP2Priority?
     
    var promisedStream: UInt32?
}

 
enum HTTP2Inbound: Equatable, Sendable {
     
    case frame(HTTP2Frame)
    case headers(HTTP2HeaderBlock)
    case pushPromise(HTTP2HeaderBlock)
}

 
 
 
 
 
 
struct HTTP2HeaderBlockAssembler: Sendable {
    var decoder: HPACKDecoder

    private struct Open: Sendable {
        var stream: UInt32
        var endStream: Bool
        var priority: HTTP2Priority?
        var promisedStream: UInt32?
        var continuations = 0
    }

    private var open: Open?
    private var fragments: [UInt8] = []

    init(decoder: HPACKDecoder) {
        self.decoder = decoder
    }

     
    var bufferedBytes: Int { fragments.count }

     
     
    var isBlockOpen: Bool { open != nil }

     
    mutating func take(_ frame: HTTP2Frame) throws -> HTTP2Inbound? {
        if var block = open {
            guard case .continuation(let continuation) = frame, continuation.stream == block.stream else {
                throw HTTP2Error.connection(.protocolError, .headerBlockInterrupted)
            }
            block.continuations += 1
            guard block.continuations <= decoder.limits.maximumContinuations else {
                throw HTTP2Error.connection(.enhanceYourCalm, .headerBlockTooLarge)
            }
            open = block
            try collect(continuation.fragment)
            return continuation.endHeaders ? try finish() : nil
        }
        switch frame {
        case .headers(let headers):
            open = Open(stream: headers.stream, endStream: headers.endStream, priority: headers.priority)
            try collect(headers.fragment)
            return headers.endHeaders ? try finish() : nil
        case .pushPromise(let push):
            open = Open(stream: push.stream, endStream: false, promisedStream: push.promisedStream)
            try collect(push.fragment)
            return push.endHeaders ? try finish() : nil
        case .continuation:
            throw HTTP2Error.connection(.protocolError, .continuationWithoutHeaders)
        default:
            return .frame(frame)
        }
    }

    private mutating func collect(_ fragment: Data) throws {
        guard fragment.count <= decoder.limits.maximumBlockBytes - fragments.count else {
            throw HTTP2Error.connection(.enhanceYourCalm, .headerBlockTooLarge)
        }
        fragments.append(contentsOf: fragment)
    }

     
     
     
    private mutating func finish() throws -> HTTP2Inbound {
        guard let block = open else { throw HTTP2Error.connection(.internalError, .continuationWithoutHeaders) }
        let bytes = fragments
        open = nil
        fragments = []
        let fields: [HPACKField]
        do {
            fields = try decoder.decode(bytes)
        } catch let error as HPACKError where error.leavesTableInStep {
            throw HTTP2Error.stream(block.promisedStream ?? block.stream, .protocolError, .headerListTooLarge(error))
        } catch let error as HPACKError {
            throw HTTP2Error.connection(.compressionError, .compression(error))
        }
        let assembled = HTTP2HeaderBlock(stream: block.stream, fields: fields, endStream: block.endStream,
                                                priority: block.priority, promisedStream: block.promisedStream)
        return block.promisedStream == nil ? .headers(assembled) : .pushPromise(assembled)
    }
}

 
 
enum HTTP2Malformed: Error, Equatable, Sendable {
     
    case invalidName(String)
     
     
    case invalidValue(String)
     
    case connectionSpecific(String)
     
    case pseudoAfterRegular(String)
     
    case repeatedPseudo(String)
     
    case unexpectedPseudo(String)
     
    case missingPseudo(String)
     
    case invalidPseudoValue(String)
     
     
    case authorityMismatch
     
     
    case repeatedHost
     
    case invalidContentLength
    case contentLengthMismatch
     
    case interimWithEndStream
     
     
    case tooManyInterimResponses
     
    case headersAfterHeadWithoutEndStream
     
    case dataBeforeHeaders
}

 
 
enum HTTP2FieldRules {
     
    static let connectionSpecific: Set<String> = [#"connection"#, #"proxy-connection"#, #"keep-alive"#, #"transfer-encoding"#,
                                                  #"upgrade"#]

     
     
    static func isValidName(_ name: String) -> Bool {
        guard !name.unicodeScalars.isEmpty else { return false }
        return name.unicodeScalars.allSatisfy { isTokenScalar($0) && !(0x41...0x5A).contains($0.value) }
    }

     
     
    static func isValidValue(_ value: String) -> Bool {
        !hasForbiddenCharacter(value) && !hasOuterWhitespace(value)
    }

     
     
    static func hasForbiddenCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value == 0x00 || $0.value == 0x0A || $0.value == 0x0D }
    }

     
    static func hasOuterWhitespace(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        if let first = scalars.first, first.value == 0x20 || first.value == 0x09 { return true }
        if let last = scalars.last, last.value == 0x20 || last.value == 0x09 { return true }
        return false
    }

     
    static func trimmingOuterWhitespace(_ value: String) -> String {
        hasOuterWhitespace(value) ? value.trimmingCharacters(in: ModuleHTTPWhitespace.optional) : value
    }

     
    static func isTokenScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        case 0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F, 0x60, 0x7C, 0x7E: return true
        default: return false
        }
    }

    static func isToken(_ text: String) -> Bool {
        !text.unicodeScalars.isEmpty && text.unicodeScalars.allSatisfy(isTokenScalar)
    }

     
     
    static func isValidTarget(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value != 0x7F }
    }

     
     
    static func asciiLowercased(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0x41...0x5A).contains($0.value) }) else { return text }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x41...0x5A).contains(scalar.value), let lower = Unicode.Scalar(scalar.value + 0x20) {
                scalars.append(lower)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}

 
struct HTTP2RequestHead: Equatable, Sendable {
    static let defaultControlOrder = [#":method"#, #":scheme"#, #":authority"#, #":path"#, #":protocol"#]

    var method: String
     
    var scheme: String?
    var authority: String?
     
    var path: String?
     
    var connectProtocol: String?
     
     
    var headers: ModuleHTTPHeaders
     
     
    var neverIndexed: Set<String> = []
     
     
    var controlOrder: [String] = defaultControlOrder
     
     
     
    var authorityAsItCame: String?
    var hostAsItCame: String?

     
     
     
    var effectiveAuthority: String? { authority ?? headers.first(#"host"#) }

     
     
     
     
     
     
     
    func fields() throws -> [HPACKField] {
        var headers = self.headers
        var authority = self.authority
        let hosts = headers.values(#"host"#)
        guard hosts.count <= 1 else { throw HTTP2Malformed.repeatedHost }
        if let current = authority, let host = hosts.first.map(HTTP2FieldRules.trimmingOuterWhitespace) {
            if !Self.same(host, hostAsItCame) {
                authority = host
                headers.remove(#"host"#)
            } else if !Self.same(current, authorityAsItCame) {
                headers.remove(#"host"#)
            }
        }
        var control: [String: String] = [:]
        control[#":method"#] = method
        control[#":scheme"#] = scheme
        control[#":authority"#] = authority
        control[#":path"#] = path
        control[#":protocol"#] = connectProtocol
        return try HTTP2Message.fields(control: control, order: controlOrder + Self.defaultControlOrder, headers: headers,
                                              neverIndexed: neverIndexed)
    }

     
     
    private static func same(_ value: String, _ other: String?) -> Bool {
        other.map { HPACKOctets.same(value, $0) } ?? false
    }
}

 
struct HTTP2ResponseHead: Equatable, Sendable {
    var status: Int
    var headers: ModuleHTTPHeaders
    var neverIndexed: Set<String> = []

    var isInterim: Bool { (100..<200).contains(status) }

    func fields() throws -> [HPACKField] {
        guard HTTP2Message.isValidStatus(status) else { throw HTTP2Malformed.invalidPseudoValue(#":status"#) }
        return try HTTP2Message.fields(control: [#":status"#: String(status)], order: [#":status"#], headers: headers,
                                              neverIndexed: neverIndexed)
    }
}

 
 
struct HTTP2Trailers: Equatable, Sendable {
    var headers: ModuleHTTPHeaders
    var neverIndexed: Set<String> = []

    func fields() throws -> [HPACKField] {
        try HTTP2Message.fields(control: [:], order: [], headers: headers, neverIndexed: neverIndexed)
    }
}

 
 
 
 
 
 
struct HTTP2Validation: Equatable, Sendable {
     
     
     
     
     
    var allowsOuterWhitespace: Bool
     
     
     
     
     
    var allowsHostAuthorityMismatch: Bool

    static let lenient = HTTP2Validation(allowsOuterWhitespace: true, allowsHostAuthorityMismatch: true)
     
    static let strict = HTTP2Validation(allowsOuterWhitespace: false, allowsHostAuthorityMismatch: false)
}

 
 
 
enum HTTP2Message {
    private static let requestControl: Set<String> = [#":method"#, #":scheme"#, #":authority"#, #":path"#, #":protocol"#]

    static func request(_ fields: [HPACKField], validation: HTTP2Validation = .lenient) throws -> HTTP2RequestHead {
        let section = try split(fields, control: requestControl, validation: validation)
        let control = section.control
        guard let method = control[#":method"#] else { throw HTTP2Malformed.missingPseudo(#":method"#) }
        guard HTTP2FieldRules.isToken(method) else { throw HTTP2Malformed.invalidPseudoValue(#":method"#) }
        let scheme = control[#":scheme"#]
        let authority = control[#":authority"#]
        let path = control[#":path"#]
        let connectProtocol = control[#":protocol"#]
        let connect = method == #"CONNECT"#
        if connectProtocol != nil, !connect { throw HTTP2Malformed.unexpectedPseudo(#":protocol"#) }
        if connect, connectProtocol == nil {
             
            if scheme != nil { throw HTTP2Malformed.unexpectedPseudo(#":scheme"#) }
            if path != nil { throw HTTP2Malformed.unexpectedPseudo(#":path"#) }
            if authority == nil { throw HTTP2Malformed.missingPseudo(#":authority"#) }
        } else {
            guard let scheme else { throw HTTP2Malformed.missingPseudo(#":scheme"#) }
            guard let path else { throw HTTP2Malformed.missingPseudo(#":path"#) }
            guard isValidScheme(scheme) else { throw HTTP2Malformed.invalidPseudoValue(#":scheme"#) }
            guard !path.isEmpty, HTTP2FieldRules.isValidTarget(path) else {
                throw HTTP2Malformed.invalidPseudoValue(#":path"#)
            }
            if isWebScheme(scheme), !path.hasPrefix(#"/"#), !(method == #"OPTIONS"# && path == #"*"#) {
                throw HTTP2Malformed.invalidPseudoValue(#":path"#)
            }
        }
        if let authority {
             
            guard !authority.isEmpty, HTTP2FieldRules.isValidTarget(authority),
                  !(isWebScheme(scheme ?? #""#) && authority.contains(#"@"#)) else {
                throw HTTP2Malformed.invalidPseudoValue(#":authority"#)
            }
        }
        let hosts = section.headers.values(#"host"#)
        guard hosts.count <= 1 else { throw HTTP2Malformed.repeatedHost }
        if !validation.allowsHostAuthorityMismatch, let authority, let host = hosts.first,
           normalized(host, scheme: scheme) != normalized(authority, scheme: scheme) {
            throw HTTP2Malformed.authorityMismatch
        }
        return HTTP2RequestHead(method: method, scheme: scheme, authority: authority, path: path,
                                       connectProtocol: connectProtocol, headers: section.headers,
                                       neverIndexed: section.neverIndexed, controlOrder: section.order,
                                       authorityAsItCame: authority, hostAsItCame: hosts.first)
    }

    static func response(_ fields: [HPACKField], validation: HTTP2Validation = .lenient) throws -> HTTP2ResponseHead {
        let section = try split(fields, control: [#":status"#], validation: validation)
        guard let text = section.control[#":status"#] else { throw HTTP2Malformed.missingPseudo(#":status"#) }
        guard text.unicodeScalars.count == 3, text.unicodeScalars.allSatisfy({ (0x30...0x39).contains($0.value) }),
              let status = Int(text), isValidStatus(status) else {
            throw HTTP2Malformed.invalidPseudoValue(#":status"#)
        }
        return HTTP2ResponseHead(status: status, headers: section.headers, neverIndexed: section.neverIndexed)
    }

    static func trailers(_ fields: [HPACKField], validation: HTTP2Validation = .lenient) throws -> HTTP2Trailers {
        let section = try split(fields, control: [], validation: validation)
        return HTTP2Trailers(headers: section.headers, neverIndexed: section.neverIndexed)
    }

     
    static func isValidStatus(_ status: Int) -> Bool {
        (100...999).contains(status) && status != 101
    }

    private struct Section {
        var control: [String: String] = [:]
        var order: [String] = []
        var headers = ModuleHTTPHeaders()
        var neverIndexed: Set<String> = []
    }

     
     
    private static func split(_ fields: [HPACKField], control allowed: Set<String>,
                              validation: HTTP2Validation) throws -> Section {
        var section = Section()
        var regular = false
        for field in fields {
            let name = field.name
            if name.unicodeScalars.first == ":" {
                guard !regular else { throw HTTP2Malformed.pseudoAfterRegular(name) }
                guard allowed.contains(name) else { throw HTTP2Malformed.unexpectedPseudo(name) }
                guard section.control[name] == nil else { throw HTTP2Malformed.repeatedPseudo(name) }
                section.control[name] = try checkedValue(field, validation)
                section.order.append(name)
            } else {
                regular = true
                guard HTTP2FieldRules.isValidName(name) else { throw HTTP2Malformed.invalidName(name) }
                let value = try checkedValue(field, validation)
                if HTTP2FieldRules.connectionSpecific.contains(name) { throw HTTP2Malformed.connectionSpecific(name) }
                if name == #"te"#, value.lowercased() != #"trailers"# { throw HTTP2Malformed.connectionSpecific(name) }
                section.headers.add(name, value)
            }
            if field.indexing == .neverIndexed { section.neverIndexed.insert(name) }
        }
        return section
    }

     
     
     
     
    private static func checkedValue(_ field: HPACKField, _ validation: HTTP2Validation) throws -> String {
        guard !HTTP2FieldRules.hasForbiddenCharacter(field.value) else { throw HTTP2Malformed.invalidValue(field.name) }
        guard HTTP2FieldRules.hasOuterWhitespace(field.value) else { return field.value }
        guard validation.allowsOuterWhitespace else { throw HTTP2Malformed.invalidValue(field.name) }
        return HTTP2FieldRules.trimmingOuterWhitespace(field.value)
    }

     
     
     
     
     
     
    static func fields(control: [String: String], order: [String], headers: ModuleHTTPHeaders,
                       neverIndexed: Set<String>) throws -> [HPACKField] {
        var out: [HPACKField] = []
        out.reserveCapacity(control.count + headers.fields.count)
        var written: Set<String> = []
        for name in order where !written.contains(name) {
            guard let value = control[name] else { continue }
            written.insert(name)
            guard HTTP2FieldRules.isValidValue(value) else { throw HTTP2Malformed.invalidValue(name) }
            out.append(field(name, value, neverIndexed))
        }
        let named = Set(headers.tokens(#"connection"#))
        for header in headers.fields {
            let name = HTTP2FieldRules.asciiLowercased(header.name)
            guard HTTP2FieldRules.isValidName(name) else { throw HTTP2Malformed.invalidName(name) }
            if HTTP2FieldRules.connectionSpecific.contains(name) || named.contains(name) { continue }
            let value = header.value.trimmingCharacters(in: ModuleHTTPWhitespace.optional)
            guard HTTP2FieldRules.isValidValue(value) else { throw HTTP2Malformed.invalidValue(name) }
            if name == #"te"#, value.lowercased() != #"trailers"# { continue }
            out.append(field(name, value, neverIndexed))
        }
        return out
    }

    private static func field(_ name: String, _ value: String, _ neverIndexed: Set<String>) -> HPACKField {
        HPACKField(name, value, indexing: neverIndexed.contains(name) ? .neverIndexed
            : HPACKIndexing.preferred(name: name, value: value))
    }

     
    private static func isValidScheme(_ scheme: String) -> Bool {
        guard let first = scheme.unicodeScalars.first, first.isASCIILetter else { return false }
        return scheme.unicodeScalars.allSatisfy {
            $0.isASCIILetter || (0x30...0x39).contains($0.value) || $0 == "+" || $0 == "-" || $0 == "."
        }
    }

    private static func isWebScheme(_ scheme: String) -> Bool {
        let lower = scheme.lowercased()
        return lower == #"http"# || lower == #"https"#
    }

     
     
     
    private static func normalized(_ authority: String, scheme: String?) -> String {
        var lower = authority.lowercased()
        if lower.hasSuffix(#":"#) { lower.removeLast() }
        switch scheme?.lowercased() {
        case #"https"#? where lower.hasSuffix(#":443"#): return String(lower.dropLast(4))
        case #"http"#? where lower.hasSuffix(#":80"#): return String(lower.dropLast(3))
        default: return lower
        }
    }
}

private extension Unicode.Scalar {
    var isASCIILetter: Bool { (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) }
}

 
enum HTTP2MessagePart: Equatable, Sendable {
    case request(HTTP2RequestHead)
     
    case response(HTTP2ResponseHead)
    case trailers(HTTP2Trailers)
}

 
 
 
 
 
struct HTTP2MessageTracker: Sendable {
    enum Carrying: Equatable, Sendable {
        case request
         
         
        case response(toMethod: String)
    }

    private enum Stage: Sendable {
        case head
        case body
        case ended
    }

     
     
    static let maximumInterimResponses = 16

    let stream: UInt32
    let carrying: Carrying
    let validation: HTTP2Validation
    private var stage = Stage.head
    private var interimResponses = 0
    private var expectedLength: Int64?
    private var receivedLength: Int64 = 0

    init(stream: UInt32, carrying: Carrying, validation: HTTP2Validation = .lenient) {
        self.stream = stream
        self.carrying = carrying
        self.validation = validation
    }

     
    var isComplete: Bool {
        if case .ended = stage { return true }
        return false
    }

    mutating func receive(_ block: HTTP2HeaderBlock) throws -> HTTP2MessagePart {
        do {
            return try take(block)
        } catch let reason as HTTP2Malformed {
            throw HTTP2Error.stream(stream, .protocolError, .malformed(reason))
        }
    }

    mutating func receive(_ data: HTTP2DataFrame) throws {
        switch stage {
        case .ended:
            throw HTTP2Error.stream(stream, .streamClosed, .afterEndStream)
        case .head:
            throw HTTP2Error.stream(stream, .protocolError, .malformed(.dataBeforeHeaders))
        case .body:
            receivedLength += Int64(data.payload.count)
            if let expectedLength, receivedLength > expectedLength {
                throw HTTP2Error.stream(stream, .protocolError, .malformed(.contentLengthMismatch))
            }
            if data.endStream {
                do { try end() } catch let reason as HTTP2Malformed {
                    throw HTTP2Error.stream(stream, .protocolError, .malformed(reason))
                }
            }
        }
    }

    private mutating func take(_ block: HTTP2HeaderBlock) throws -> HTTP2MessagePart {
        switch stage {
        case .ended:
            throw HTTP2Error.stream(stream, .streamClosed, .afterEndStream)
        case .body:
            guard block.endStream else { throw HTTP2Malformed.headersAfterHeadWithoutEndStream }
            let trailers = try HTTP2Message.trailers(block.fields, validation: validation)
            try end()
            return .trailers(trailers)
        case .head:
            switch carrying {
            case .request:
                let head = try HTTP2Message.request(block.fields, validation: validation)
                expectedLength = head.method == #"CONNECT"# ? nil : try Self.contentLength(head.headers)
                try begin(endStream: block.endStream)
                return .request(head)
            case .response(let method):
                let head = try HTTP2Message.response(block.fields, validation: validation)
                if head.isInterim {
                    guard !block.endStream else { throw HTTP2Malformed.interimWithEndStream }
                    interimResponses += 1
                    guard interimResponses <= Self.maximumInterimResponses else { throw HTTP2Malformed.tooManyInterimResponses }
                    return .response(head)
                }
                let noContent = method == #"HEAD"# || head.status == 204 || head.status == 304
                    || (method == #"CONNECT"# && (200..<300).contains(head.status))
                expectedLength = noContent ? nil : try Self.contentLength(head.headers)
                try begin(endStream: block.endStream)
                return .response(head)
            }
        }
    }

    private mutating func begin(endStream: Bool) throws {
        stage = .body
        if endStream { try end() }
    }

    private mutating func end() throws {
        if let expectedLength, expectedLength != receivedLength { throw HTTP2Malformed.contentLengthMismatch }
        stage = .ended
    }

    private static func contentLength(_ headers: ModuleHTTPHeaders) throws -> Int64? {
        do {
            return try ModuleHTTPFraming.contentLength(headers)
        } catch {
            throw HTTP2Malformed.invalidContentLength
        }
    }
}
#endif
