#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 

 
 
 
struct HTTP2ErrorCode: RawRepresentable, Hashable, Sendable {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let noError = HTTP2ErrorCode(rawValue: 0x0)
    static let protocolError = HTTP2ErrorCode(rawValue: 0x1)
    static let internalError = HTTP2ErrorCode(rawValue: 0x2)
    static let flowControlError = HTTP2ErrorCode(rawValue: 0x3)
    static let settingsTimeout = HTTP2ErrorCode(rawValue: 0x4)
    static let streamClosed = HTTP2ErrorCode(rawValue: 0x5)
    static let frameSizeError = HTTP2ErrorCode(rawValue: 0x6)
    static let refusedStream = HTTP2ErrorCode(rawValue: 0x7)
    static let cancel = HTTP2ErrorCode(rawValue: 0x8)
    static let compressionError = HTTP2ErrorCode(rawValue: 0x9)
    static let connectError = HTTP2ErrorCode(rawValue: 0xA)
    static let enhanceYourCalm = HTTP2ErrorCode(rawValue: 0xB)
    static let inadequateSecurity = HTTP2ErrorCode(rawValue: 0xC)
    static let http11Required = HTTP2ErrorCode(rawValue: 0xD)
}

 
 
enum HTTP2Fault: Equatable, Sendable {
     
    case badPreface
     
    case firstFrameNotSettings
     
     
    case frameTooLarge(Int)
     
    case badFrameLength(HTTP2FrameType)
     
    case needsStream(HTTP2FrameType)
     
    case needsStreamZero(HTTP2FrameType)
     
    case badStreamIdentifier
     
    case paddingTooLong
     
    case badSetting(HTTP2Setting)
     
     
    case pushPromiseRefused
     
    case zeroWindowIncrement
     
    case badWindowIncrement(UInt32)
     
    case continuationWithoutHeaders
     
     
    case headerBlockInterrupted
     
     
    case headerBlockTooLarge
     
    case compression(HPACKError)
     
    case headerListTooLarge(HPACKError)
     
    case malformed(HTTP2Malformed)
     
    case afterEndStream
}

 
 
enum HTTP2Error: Error, Equatable, Sendable {
    case connection(HTTP2ErrorCode, HTTP2Fault)
    case stream(UInt32, HTTP2ErrorCode, HTTP2Fault)

    var code: HTTP2ErrorCode {
        switch self {
        case .connection(let code, _), .stream(_, let code, _): return code
        }
    }

    var fault: HTTP2Fault {
        switch self {
        case .connection(_, let fault), .stream(_, _, let fault): return fault
        }
    }
}

enum HTTP2FrameType: UInt8, Sendable {
    case data = 0x0
    case headers = 0x1
    case priority = 0x2
    case rstStream = 0x3
    case settings = 0x4
    case pushPromise = 0x5
    case ping = 0x6
    case goaway = 0x7
    case windowUpdate = 0x8
    case continuation = 0x9
}

 
enum HTTP2Flags {
    static let endStream: UInt8 = 0x01
    static let ack: UInt8 = 0x01
    static let endHeaders: UInt8 = 0x04
    static let padded: UInt8 = 0x08
    static let priority: UInt8 = 0x20
}

 
 
struct HTTP2Priority: Equatable, Sendable {
    var exclusive: Bool
    var dependency: UInt32
     
    var weight: UInt8
}

struct HTTP2SettingIdentifier: RawRepresentable, Hashable, Sendable {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    static let headerTableSize = HTTP2SettingIdentifier(rawValue: 0x1)
    static let enablePush = HTTP2SettingIdentifier(rawValue: 0x2)
    static let maxConcurrentStreams = HTTP2SettingIdentifier(rawValue: 0x3)
    static let initialWindowSize = HTTP2SettingIdentifier(rawValue: 0x4)
    static let maxFrameSize = HTTP2SettingIdentifier(rawValue: 0x5)
    static let maxHeaderListSize = HTTP2SettingIdentifier(rawValue: 0x6)
     
    static let enableConnectProtocol = HTTP2SettingIdentifier(rawValue: 0x8)
}

 
 
struct HTTP2Setting: Equatable, Sendable {
    var identifier: HTTP2SettingIdentifier
    var value: UInt32

    init(_ identifier: HTTP2SettingIdentifier, _ value: UInt32) {
        self.identifier = identifier
        self.value = value
    }

     
    func violation(fromServer: Bool) -> HTTP2Error? {
        switch identifier {
        case .enablePush where value > 1 || (value == 1 && fromServer):
            return .connection(.protocolError, .badSetting(self))
        case .initialWindowSize where value > HTTP2Frame.largestWindowSize:
            return .connection(.flowControlError, .badSetting(self))
        case .maxFrameSize where value < HTTP2Frame.defaultMaximumFrameSize
            || value > HTTP2Frame.largestMaximumFrameSize:
            return .connection(.protocolError, .badSetting(self))
         
        case .enableConnectProtocol where value > 1:
            return .connection(.protocolError, .badSetting(self))
        default:
            return nil
        }
    }
}

 
 
struct HTTP2Settings: Equatable, Sendable {
    var headerTableSize = 4096
    var enablePush = true
     
    var maxConcurrentStreams: Int?
    var initialWindowSize = 65_535
    var maxFrameSize = 16_384
     
    var maxHeaderListSize: Int?
    var enableConnectProtocol = false

    init() {}

     
    mutating func apply(_ settings: [HTTP2Setting]) {
        for setting in settings {
            let value = Int(setting.value)
            switch setting.identifier {
            case .headerTableSize: headerTableSize = value
            case .enablePush: enablePush = value == 1
            case .maxConcurrentStreams: maxConcurrentStreams = value
            case .initialWindowSize: initialWindowSize = value
            case .maxFrameSize: maxFrameSize = value
            case .maxHeaderListSize: maxHeaderListSize = value
            case .enableConnectProtocol: enableConnectProtocol = value == 1
            default: break
            }
        }
    }
}

struct HTTP2DataFrame: Equatable, Sendable {
    var stream: UInt32
    var payload: Data
    var endStream = false
     
    var padding: UInt8?

     
     
    var flowControlledLength: Int { payload.count + (padding.map { Int($0) + 1 } ?? 0) }
}

struct HTTP2HeadersFrame: Equatable, Sendable {
    var stream: UInt32
    var fragment: Data
    var endStream = false
    var endHeaders = true
    var priority: HTTP2Priority?
    var padding: UInt8?
}

struct HTTP2PushPromiseFrame: Equatable, Sendable {
    var stream: UInt32
    var promisedStream: UInt32
    var fragment: Data
    var endHeaders = true
    var padding: UInt8?
}

struct HTTP2ContinuationFrame: Equatable, Sendable {
    var stream: UInt32
    var fragment: Data
    var endHeaders = true
}

enum HTTP2Frame: Equatable, Sendable {
    case data(HTTP2DataFrame)
    case headers(HTTP2HeadersFrame)
    case priority(stream: UInt32, HTTP2Priority)
    case rstStream(stream: UInt32, HTTP2ErrorCode)
    case settings([HTTP2Setting])
    case settingsAck
    case pushPromise(HTTP2PushPromiseFrame)
    case ping(opaque: UInt64, ack: Bool)
    case goaway(lastStream: UInt32, HTTP2ErrorCode, debugData: Data)
    case windowUpdate(stream: UInt32, increment: UInt32)
    case continuation(HTTP2ContinuationFrame)
     
     
    case unknown(type: UInt8, flags: UInt8, stream: UInt32, payload: Data)

     
    var stream: UInt32 {
        switch self {
        case .data(let frame): return frame.stream
        case .headers(let frame): return frame.stream
        case .priority(let stream, _), .rstStream(let stream, _), .windowUpdate(let stream, _): return stream
        case .settings, .settingsAck, .ping, .goaway: return 0
        case .pushPromise(let frame): return frame.stream
        case .continuation(let frame): return frame.stream
        case .unknown(_, _, let stream, _): return stream
        }
    }

     
    static let clientPrefaceBytes: [UInt8] = [
        0x50, 0x52, 0x49, 0x20, 0x2A, 0x20, 0x48, 0x54, 0x54, 0x50, 0x2F, 0x32, 0x2E, 0x30, 0x0D, 0x0A,
        0x0D, 0x0A, 0x53, 0x4D, 0x0D, 0x0A, 0x0D, 0x0A,
    ]
    static let clientPreface = Data(clientPrefaceBytes)

     
    static let headerLength = 9
     
     
    static let defaultMaximumFrameSize: UInt32 = 16_384
    static let largestMaximumFrameSize: UInt32 = 16_777_215
     
    static let largestWindowSize: UInt32 = 0x7FFF_FFFF
    static let largestStreamIdentifier: UInt32 = 0x7FFF_FFFF
}

extension HTTP2Frame {
     
     
    static func parse(type: UInt8, flags: UInt8, stream: UInt32, payload: ArraySlice<UInt8>,
                      peer: HTTP2FrameReader.Peer, acceptsPushPromise: Bool) throws -> HTTP2Frame {
        guard let known = HTTP2FrameType(rawValue: type) else {
            return .unknown(type: type, flags: flags, stream: stream, payload: Data(payload))
        }
        let base = payload.startIndex
        switch known {
        case .data:
            try requireStream(stream, known)
            let (body, padding) = try unpad(payload, flags: flags, type: known, fields: 0)
            return .data(HTTP2DataFrame(stream: stream, payload: Data(body),
                                               endStream: flags & HTTP2Flags.endStream != 0, padding: padding))

        case .headers:
            try requireStream(stream, known)
            let prioritized = flags & HTTP2Flags.priority != 0
            let (body, padding) = try unpad(payload, flags: flags, type: known, fields: prioritized ? 5 : 0)
            let priority = prioritized ? Self.priority(body) : nil
            return .headers(HTTP2HeadersFrame(stream: stream, fragment: Data(body.dropFirst(prioritized ? 5 : 0)),
                                                     endStream: flags & HTTP2Flags.endStream != 0,
                                                     endHeaders: flags & HTTP2Flags.endHeaders != 0,
                                                     priority: priority, padding: padding))

        case .priority:
            try requireStream(stream, known)
             
            guard payload.count == 5 else { throw HTTP2Error.stream(stream, .frameSizeError, .badFrameLength(known)) }
            return .priority(stream: stream, Self.priority(payload))

        case .rstStream:
            try requireStream(stream, known)
            try requireLength(payload, 4, known)
            return .rstStream(stream: stream, HTTP2ErrorCode(rawValue: uint32(payload, base)))

        case .settings:
            try requireStreamZero(stream, known)
            if flags & HTTP2Flags.ack != 0 {
                try requireLength(payload, 0, known)
                return .settingsAck
            }
            guard payload.count % 6 == 0 else { throw HTTP2Error.connection(.frameSizeError, .badFrameLength(known)) }
            var settings: [HTTP2Setting] = []
            settings.reserveCapacity(payload.count / 6)
            var offset = base
            while offset < payload.endIndex {
                let identifier = UInt16(payload[offset]) << 8 | UInt16(payload[offset + 1])
                let setting = HTTP2Setting(HTTP2SettingIdentifier(rawValue: identifier), uint32(payload, offset + 2))
                if let violation = setting.violation(fromServer: peer == .server) { throw violation }
                settings.append(setting)
                offset += 6
            }
            return .settings(settings)

        case .pushPromise:
            guard peer == .server, acceptsPushPromise else { throw HTTP2Error.connection(.protocolError, .pushPromiseRefused) }
            try requireStream(stream, known)
            let (body, padding) = try unpad(payload, flags: flags, type: known, fields: 4)
            let promised = uint32(body, body.startIndex) & largestStreamIdentifier
            guard promised != 0 else { throw HTTP2Error.connection(.protocolError, .badStreamIdentifier) }
            return .pushPromise(HTTP2PushPromiseFrame(stream: stream, promisedStream: promised,
                                                             fragment: Data(body.dropFirst(4)),
                                                             endHeaders: flags & HTTP2Flags.endHeaders != 0,
                                                             padding: padding))

        case .ping:
            try requireStreamZero(stream, known)
            try requireLength(payload, 8, known)
            return .ping(opaque: UInt64(uint32(payload, base)) << 32 | UInt64(uint32(payload, base + 4)),
                         ack: flags & HTTP2Flags.ack != 0)

        case .goaway:
            try requireStreamZero(stream, known)
            guard payload.count >= 8 else { throw HTTP2Error.connection(.frameSizeError, .badFrameLength(known)) }
            return .goaway(lastStream: uint32(payload, base) & largestStreamIdentifier,
                           HTTP2ErrorCode(rawValue: uint32(payload, base + 4)), debugData: Data(payload.dropFirst(8)))

        case .windowUpdate:
            try requireLength(payload, 4, known)
            let increment = uint32(payload, base) & largestWindowSize
            guard increment != 0 else {
                 
                throw stream == 0 ? HTTP2Error.connection(.protocolError, .zeroWindowIncrement)
                    : HTTP2Error.stream(stream, .protocolError, .zeroWindowIncrement)
            }
            return .windowUpdate(stream: stream, increment: increment)

        case .continuation:
            try requireStream(stream, known)
            return .continuation(HTTP2ContinuationFrame(stream: stream, fragment: Data(payload),
                                                               endHeaders: flags & HTTP2Flags.endHeaders != 0))
        }
    }

    private static func requireStream(_ stream: UInt32, _ type: HTTP2FrameType) throws {
        guard stream != 0 else { throw HTTP2Error.connection(.protocolError, .needsStream(type)) }
    }

    private static func requireStreamZero(_ stream: UInt32, _ type: HTTP2FrameType) throws {
        guard stream == 0 else { throw HTTP2Error.connection(.protocolError, .needsStreamZero(type)) }
    }

    private static func requireLength(_ payload: ArraySlice<UInt8>, _ length: Int, _ type: HTTP2FrameType) throws {
        guard payload.count == length else { throw HTTP2Error.connection(.frameSizeError, .badFrameLength(type)) }
    }

     
     
     
    private static func unpad(_ payload: ArraySlice<UInt8>, flags: UInt8, type: HTTP2FrameType,
                              fields: Int) throws -> (ArraySlice<UInt8>, UInt8?) {
        guard flags & HTTP2Flags.padded != 0 else {
            guard payload.count >= fields else { throw HTTP2Error.connection(.frameSizeError, .badFrameLength(type)) }
            return (payload, nil)
        }
        guard payload.count >= 1 + fields else { throw HTTP2Error.connection(.frameSizeError, .badFrameLength(type)) }
        let padding = payload[payload.startIndex]
        let rest = payload.dropFirst()
        guard Int(padding) <= rest.count - fields else { throw HTTP2Error.connection(.protocolError, .paddingTooLong) }
        return (rest.dropLast(Int(padding)), padding)
    }

    private static func priority(_ bytes: ArraySlice<UInt8>) -> HTTP2Priority {
        let word = uint32(bytes, bytes.startIndex)
        return HTTP2Priority(exclusive: word & 0x8000_0000 != 0, dependency: word & largestStreamIdentifier,
                                    weight: bytes[bytes.startIndex + 4])
    }

    static func uint32(_ bytes: ArraySlice<UInt8>, _ index: Int) -> UInt32 {
        UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
    }
}

 
 
 
enum HTTP2Serializer {
    static func frame(_ frame: HTTP2Frame, maximumFrameSize: Int = Int(HTTP2Frame.defaultMaximumFrameSize)) throws -> Data {
        var payload: [UInt8] = []
        var flags: UInt8 = 0
        let type: UInt8
        let stream: UInt32
        switch frame {
        case .data(let data):
            type = HTTP2FrameType.data.rawValue
            stream = try streamIdentifier(data.stream)
            if data.endStream { flags |= HTTP2Flags.endStream }
            pad(&payload, &flags, data.padding, fields: [], body: data.payload)

        case .headers(let headers):
            type = HTTP2FrameType.headers.rawValue
            stream = try streamIdentifier(headers.stream)
            if headers.endStream { flags |= HTTP2Flags.endStream }
            if headers.endHeaders { flags |= HTTP2Flags.endHeaders }
            var fields: [UInt8] = []
            if let priority = headers.priority {
                flags |= HTTP2Flags.priority
                try append(priority, to: &fields)
            }
            pad(&payload, &flags, headers.padding, fields: fields, body: headers.fragment)

        case .priority(let id, let priority):
            type = HTTP2FrameType.priority.rawValue
            stream = try streamIdentifier(id)
            try append(priority, to: &payload)

        case .rstStream(let id, let code):
            type = HTTP2FrameType.rstStream.rawValue
            stream = try streamIdentifier(id)
            append(code.rawValue, to: &payload)

        case .settings(let settings):
            type = HTTP2FrameType.settings.rawValue
            stream = 0
            for setting in settings {
                if setting.violation(fromServer: false) != nil {
                    throw HTTP2Error.connection(.internalError, .badSetting(setting))
                }
                payload.append(UInt8(setting.identifier.rawValue >> 8))
                payload.append(UInt8(truncatingIfNeeded: setting.identifier.rawValue))
                append(setting.value, to: &payload)
            }

        case .settingsAck:
            type = HTTP2FrameType.settings.rawValue
            stream = 0
            flags = HTTP2Flags.ack

        case .pushPromise(let push):
            type = HTTP2FrameType.pushPromise.rawValue
            stream = try streamIdentifier(push.stream)
            if push.endHeaders { flags |= HTTP2Flags.endHeaders }
            var fields: [UInt8] = []
            append(try streamIdentifier(push.promisedStream), to: &fields)
            pad(&payload, &flags, push.padding, fields: fields, body: push.fragment)

        case .ping(let opaque, let ack):
            type = HTTP2FrameType.ping.rawValue
            stream = 0
            if ack { flags = HTTP2Flags.ack }
            append(UInt32(truncatingIfNeeded: opaque >> 32), to: &payload)
            append(UInt32(truncatingIfNeeded: opaque), to: &payload)

        case .goaway(let lastStream, let code, let debugData):
            type = HTTP2FrameType.goaway.rawValue
            stream = 0
            guard lastStream <= HTTP2Frame.largestStreamIdentifier else {
                throw HTTP2Error.connection(.internalError, .badStreamIdentifier)
            }
            append(lastStream, to: &payload)
            append(code.rawValue, to: &payload)
            payload.append(contentsOf: debugData)

        case .windowUpdate(let id, let increment):
            type = HTTP2FrameType.windowUpdate.rawValue
            guard id <= HTTP2Frame.largestStreamIdentifier else {
                throw HTTP2Error.connection(.internalError, .badStreamIdentifier)
            }
            stream = id
            guard increment != 0, increment <= HTTP2Frame.largestWindowSize else {
                throw HTTP2Error.connection(.internalError, .badWindowIncrement(increment))
            }
            append(increment, to: &payload)

        case .continuation(let continuation):
            type = HTTP2FrameType.continuation.rawValue
            stream = try streamIdentifier(continuation.stream)
            if continuation.endHeaders { flags |= HTTP2Flags.endHeaders }
            payload.append(contentsOf: continuation.fragment)

        case .unknown(let unknownType, let unknownFlags, let id, let body):
            type = unknownType
            flags = unknownFlags
            guard id <= HTTP2Frame.largestStreamIdentifier else {
                throw HTTP2Error.connection(.internalError, .badStreamIdentifier)
            }
            stream = id
            payload.append(contentsOf: body)
        }
        let limit = min(maximumFrameSize, Int(HTTP2Frame.largestMaximumFrameSize))
        guard payload.count <= limit else { throw HTTP2Error.connection(.internalError, .frameTooLarge(payload.count)) }
        var out = Data(capacity: HTTP2Frame.headerLength + payload.count)
        out.append(contentsOf: [UInt8(payload.count >> 16), UInt8(truncatingIfNeeded: payload.count >> 8),
                                UInt8(truncatingIfNeeded: payload.count), type, flags])
        var header: [UInt8] = []
        append(stream, to: &header)
        out.append(contentsOf: header)
        out.append(contentsOf: payload)
        return out
    }

     
     
    static func headers(stream: UInt32, block: Data, endStream: Bool, priority: HTTP2Priority? = nil,
                        maximumFrameSize: Int = Int(HTTP2Frame.defaultMaximumFrameSize)) throws -> Data {
        let size = max(min(maximumFrameSize, Int(HTTP2Frame.largestMaximumFrameSize)),
                       Int(HTTP2Frame.defaultMaximumFrameSize))
        let bytes = [UInt8](block)
        let first = min(bytes.count, size - (priority == nil ? 0 : 5))
        var out = try frame(.headers(HTTP2HeadersFrame(stream: stream, fragment: Data(bytes[0..<first]), endStream: endStream,
                                                              endHeaders: first == bytes.count, priority: priority)),
                            maximumFrameSize: size)
        var offset = first
        while offset < bytes.count {
            let end = min(bytes.count, offset + size)
            out += try frame(.continuation(HTTP2ContinuationFrame(stream: stream, fragment: Data(bytes[offset..<end]),
                                                                         endHeaders: end == bytes.count)),
                             maximumFrameSize: size)
            offset = end
        }
        return out
    }

    private static func streamIdentifier(_ stream: UInt32) throws -> UInt32 {
        guard stream != 0, stream <= HTTP2Frame.largestStreamIdentifier else {
            throw HTTP2Error.connection(.internalError, .badStreamIdentifier)
        }
        return stream
    }

    private static func append(_ value: UInt32, to out: inout [UInt8]) {
        out.append(contentsOf: [UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                                UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }

    private static func append(_ priority: HTTP2Priority, to out: inout [UInt8]) throws {
        guard priority.dependency <= HTTP2Frame.largestStreamIdentifier else {
            throw HTTP2Error.connection(.internalError, .badStreamIdentifier)
        }
        append(priority.dependency | (priority.exclusive ? 0x8000_0000 : 0), to: &out)
        out.append(priority.weight)
    }

     
    private static func pad(_ payload: inout [UInt8], _ flags: inout UInt8, _ padding: UInt8?, fields: [UInt8], body: Data) {
        if let padding {
            flags |= HTTP2Flags.padded
            payload.append(padding)
            payload.append(contentsOf: fields)
            payload.append(contentsOf: body)
            payload.append(contentsOf: repeatElement(0, count: Int(padding)))
        } else {
            payload.append(contentsOf: fields)
            payload.append(contentsOf: body)
        }
    }
}
#endif
