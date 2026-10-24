#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
struct HTTP2FrameReader: Sendable {
     
    enum Peer: Equatable, Sendable {
         
        case client
         
        case server
    }

    let peer: Peer
     
     
    var maximumFrameSize: Int
     
     
     
    let acceptsPushPromise: Bool
     
     
     
     
     
    var isBlockOpen = false

    private enum Stage: Sendable {
        case preface(matched: Int)
        case firstFrame
        case frames
        case failed(HTTP2Error)
    }

    private var stage: Stage
    private var buffer: [UInt8] = []
    private var offset = 0

     
     
    init(peer: Peer, maximumFrameSize: Int = Int(HTTP2Frame.defaultMaximumFrameSize),
         acceptsPushPromise: Bool = false, expectsPreface: Bool = true) {
        self.peer = peer
        self.maximumFrameSize = maximumFrameSize
        self.acceptsPushPromise = acceptsPushPromise
        stage = !expectsPreface ? .frames : peer == .client ? .preface(matched: 0) : .firstFrame
    }

     
    var bufferedBytes: Int { buffer.count - offset }

    mutating func append(_ data: Data) {
        if offset > 0 {
            buffer.removeFirst(offset)
            offset = 0
        }
        buffer.append(contentsOf: data)
    }

     
    mutating func next() throws -> HTTP2Frame? {
        if case .failed(let error) = stage { throw error }
        do {
            return try read()
        } catch let error as HTTP2Error {
            if case .connection = error { stage = .failed(error) }
            throw error
        }
    }

    private mutating func read() throws -> HTTP2Frame? {
        if case .preface(var matched) = stage {
             
            let preface = HTTP2Frame.clientPrefaceBytes
            while matched < preface.count, offset < buffer.count {
                guard buffer[offset] == preface[matched] else { throw HTTP2Error.connection(.protocolError, .badPreface) }
                matched += 1
                offset += 1
            }
            guard matched == preface.count else {
                stage = .preface(matched: matched)
                return nil
            }
            stage = .firstFrame
        }
        let header = HTTP2Frame.headerLength
        guard buffer.count - offset >= header else { return nil }
        let length = Int(buffer[offset]) << 16 | Int(buffer[offset + 1]) << 8 | Int(buffer[offset + 2])
        let type = buffer[offset + 3]
        let flags = buffer[offset + 4]
        let stream = HTTP2Frame.uint32(buffer[...], offset + 5) & HTTP2Frame.largestStreamIdentifier
        guard length <= maximumFrameSize else { throw HTTP2Error.connection(.frameSizeError, .frameTooLarge(length)) }
        if isBlockOpen, type != HTTP2FrameType.continuation.rawValue {
            throw HTTP2Error.connection(.protocolError, .headerBlockInterrupted)
        }
        if case .firstFrame = stage {
            guard type == HTTP2FrameType.settings.rawValue, flags & HTTP2Flags.ack == 0 else {
                throw HTTP2Error.connection(.protocolError, .firstFrameNotSettings)
            }
        }
        guard buffer.count - offset - header >= length else { return nil }
        let payload = buffer[(offset + header)..<(offset + header + length)]
        offset += header + length
        if case .firstFrame = stage { stage = .frames }
        let frame = try HTTP2Frame.parse(type: type, flags: flags, stream: stream, payload: payload, peer: peer,
                                                acceptsPushPromise: acceptsPushPromise)
        if offset == buffer.count {
             
            buffer.removeAll(keepingCapacity: buffer.capacity <= header + Int(HTTP2Frame.defaultMaximumFrameSize))
            offset = 0
        }
        return frame
    }
}
#endif
