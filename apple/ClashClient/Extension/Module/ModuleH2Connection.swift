#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 

 
 
 
struct ModuleH2Limits: Equatable, Sendable {
     
     
    var maximumConcurrentStreams: Int
     
    var streamWindow: Int
     
     
    var connectionWindow: Int
     
     
    var idleTimeout: TimeInterval = 30
     
     
     
    var backlogTimeout: TimeInterval = 10
     
     
    var maximumPeerResets = 1_000
    var peerResetWindow: TimeInterval = 30
     
    var rememberedClosedStreams = 256

     
     
    static let maximumControlBacklogFrames = 1_024
    static let maximumControlBacklogBytes = 64 * 1024

     
    static var app: ModuleH2Limits {
#if os(macOS)
        return ModuleH2Limits(maximumConcurrentStreams: 100, streamWindow: 1 << 20, connectionWindow: 4 << 20)
#else
        return ModuleH2Limits(maximumConcurrentStreams: 32, streamWindow: 128 << 10, connectionWindow: 512 << 10)
#endif
    }

     
     
    static var upstream: ModuleH2Limits {
#if os(macOS)
        return ModuleH2Limits(maximumConcurrentStreams: 100, streamWindow: 6 << 20, connectionWindow: 16 << 20)
#else
        return ModuleH2Limits(maximumConcurrentStreams: 32, streamWindow: 512 << 10, connectionWindow: 2 << 20)
#endif
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
final class ModuleH2BufferBudget {
    static var platformLimit: Int {
#if os(macOS)
        return 64 << 20
#else
        return 4 << 20
#endif
    }

    let limit: Int
    private(set) var held = 0
    private(set) var peak = 0
     
    private var holders: [ObjectIdentifier: Int] = [:]
    private var waiting: [ObjectIdentifier: () -> Void] = [:]

    init(limit: Int = ModuleH2BufferBudget.platformLimit) {
        self.limit = limit
    }

     
     
    func share(floor: Int) -> Int {
        max(floor, limit / max(1, holders.count))
    }

     
     
    fileprivate func allowsCredit(_ connection: ObjectIdentifier, floor: Int) -> Bool {
        held <= limit || (holders[connection] ?? 0) <= share(floor: floor)
    }

     
     
     
    var onMismatch: (_ recorded: Int, _ counted: Int) -> Void = { recorded, counted in
        assertionFailure(#"h2 buffer budget: a connection ended counting \#(counted) bytes held, the budget recorded \#(recorded)"#)
    }

     
    func hold(_ count: Int, by connection: ObjectIdentifier) {
        guard count > 0 else { return }
        held += count
        peak = max(peak, held)
        holders[connection, default: 0] += count
    }

     
     
    fileprivate func release(_ count: Int, by connection: ObjectIdentifier) {
        guard count > 0 else { return }
        held = max(0, held - count)
        let left = (holders[connection] ?? 0) - count
        holders[connection] = left > 0 ? left : nil
        guard !waiting.isEmpty else { return }
        let woken = waiting
        waiting = [:]
        woken.values.forEach { $0() }
    }

     
     
     
    fileprivate func forget(_ connection: ObjectIdentifier, counted: Int) {
        waiting[connection] = nil
        let recorded = holders.removeValue(forKey: connection) ?? 0
        if recorded != counted { onMismatch(recorded, counted) }
        held = max(0, held - recorded)
        guard recorded > 0, !waiting.isEmpty else { return }
        let woken = waiting
        waiting = [:]
        woken.values.forEach { $0() }
    }

    fileprivate func wait(_ key: ObjectIdentifier, _ wake: @escaping () -> Void) {
        waiting[key] = wake
    }

}

 
enum ModuleH2StreamEnd: Equatable, Sendable {
     
    case finished
     
    case reset(HTTP2ErrorCode)
     
    case resetHere(HTTP2ErrorCode)
     
     
    case refused
     
    case lost(String)
}

 
final class ModuleH2Stream {
    let id: UInt32
    fileprivate weak var connection: ModuleH2Connection?
     
     
    fileprivate var tracker: HTTP2MessageTracker

     
    var onResponse: ((HTTP2ResponseHead) -> Void)?
     
    var onTrailers: ((HTTP2Trailers) -> Void)?
     
     
    var onData: ((Data, Bool) -> Void)?
     
    var onEnd: ((ModuleH2StreamEnd) -> Void)?

    fileprivate enum Outbound {
        case head([HPACKField], endStream: Bool, completion: ((Bool) -> Void)?)
        case data(Data, endStream: Bool, completion: ((Bool) -> Void)?)

        var completion: ((Bool) -> Void)? {
            switch self {
            case .head(_, _, let completion), .data(_, _, let completion): return completion
            }
        }
    }

    fileprivate var outbound: [Outbound] = []
     
     
    fileprivate var sendWindow: Int
     
    fileprivate var receiveWindow: Int
     
    fileprivate var uncredited = 0
    fileprivate var localEnded = false
    fileprivate var remoteEnded = false
    fileprivate var over = false
     
     
    fileprivate var headSent = false
     
     
    fileprivate var creditedAtEnd = false
     
     
     
     
     
    var creditsConnectionOnReceipt = false
     
    fileprivate var connectionCreditedAhead = 0
     
    fileprivate var pendingReset: HTTP2ErrorCode?

    fileprivate init(id: UInt32, connection: ModuleH2Connection, carrying: HTTP2MessageTracker.Carrying,
                     sendWindow: Int, receiveWindow: Int) {
        self.id = id
        self.connection = connection
        tracker = HTTP2MessageTracker(stream: id, carrying: carrying)
        self.sendWindow = sendWindow
        self.receiveWindow = receiveWindow
    }

     
    var queuedBytes: Int {
        outbound.reduce(0) { total, item in
            if case .data(let data, _, _) = item { return total + data.count }
            return total
        }
    }

    var isOver: Bool { over }
     
     
    var isRemoteEnded: Bool { remoteEnded }
     
    var isLocalEnded: Bool { localEnded }

     
     
     
     
    func sendHead(_ fields: [HPACKField], endStream: Bool, completion: ((Bool) -> Void)? = nil) {
        guard !over, !localEnded else { completion?(false); return }
        if endStream { localEnded = true }
        outbound.append(.head(fields, endStream: endStream, completion: completion))
        connection?.flush()
    }

     
     
    func sendData(_ data: Data, endStream: Bool, completion: ((Bool) -> Void)? = nil) {
        guard !over, !localEnded else { completion?(false); return }
        if endStream { localEnded = true }
        outbound.append(.data(data, endStream: endStream, completion: completion))
        connection?.flush()
    }

     
    func sendTrailers(_ fields: [HPACKField], completion: ((Bool) -> Void)? = nil) {
        sendHead(fields, endStream: true, completion: completion)
    }

     
     
    func consumed(_ count: Int) {
        guard count > 0 else { return }
        connection?.consumed(count, on: self)
    }

     
    func reset(_ code: HTTP2ErrorCode) {
        connection?.reset(self, code)
    }

     
     
    func resetAfterSending(_ code: HTTP2ErrorCode) {
        connection?.resetAfterSending(self, code)
    }
}

final class ModuleH2Connection {
    enum Role: Equatable {
         
        case server
         
        case client
    }

    let role: Role
    private let transport: ModuleStream
    private let queue: DispatchQueue
    private let limits: ModuleH2Limits
    private let say: (String) -> Void
     
    private let buffers: ModuleH2BufferBudget?
     
    private var heldHere = 0
     
    private var creditsHeld = false
     
    private var pendingRaise = 0
    private var reader: HTTP2FrameReader
    private var assembler: HTTP2HeaderBlockAssembler
    private var encoder = HPACKEncoder()
    private var peerSettings = HTTP2Settings()
    private var streams: [UInt32: ModuleH2Stream] = [:]
     
     
    private var closed: [UInt32] = []
    private var closedSet: Set<UInt32> = []
     
    private var lastPeerStream: UInt32 = 0
     
    private var nextStream: UInt32 = 1
     
    private var highestOpened: UInt32 = 0
    private var sendWindow = 65_535
    private var receiveWindow = 65_535
    private var uncredited = 0
     
    private var ready: [UInt32] = []
    private var writing = false
     
    private var flushing = false
    private var flushAgain = false
    private var control: [Data] = []
    private var controlBytes = 0
     
    private var readPaused = false
    private var backlogTimer: ModuleDeadline?
     
    private var peerEnded: String?
     
    private var resetWindowStart: UInt64 = 0
    private var resetsInWindow = 0
     
    private var headerHeld = 0
    private var receivedGoaway: UInt32?
    private var sentGoaway = false
     
     
    private var readingFailed = false
    private var ended = false
    private var idleTimer: ModuleDeadline?

     
    var onRequest: ((ModuleH2Stream, HTTP2RequestHead) -> Void)?
     
     
    var onStreamClosed: (() -> Void)?
     
    var onEnd: ((String) -> Void)?

    init(transport: ModuleStream, role: Role, queue: DispatchQueue, limits: ModuleH2Limits, buffers: ModuleH2BufferBudget? = nil,
         log: @escaping (String) -> Void) {
        self.transport = transport
        self.role = role
        self.queue = queue
        self.limits = limits
        self.buffers = buffers
        say = log
        reader = HTTP2FrameReader(peer: role == .server ? .client : .server)
        assembler = HTTP2HeaderBlockAssembler(decoder: HPACKDecoder(limits: role == .server ? .request : .response))
    }

    var isEnded: Bool { ended }
    var openStreamCount: Int { streams.count }
     
    var controlBacklog: Int { control.count }

     
     
    var acceptsNewStreams: Bool {
        role == .client && !ended && receivedGoaway == nil && !sentGoaway && nextStream <= HTTP2Frame.largestStreamIdentifier
    }

     
    var canOpenStream: Bool {
        guard acceptsNewStreams else { return false }
        let cap = min(limits.maximumConcurrentStreams, peerSettings.maxConcurrentStreams ?? Int.max)
        return streams.count < cap
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(queue))
        var settings = [HTTP2Setting(.initialWindowSize, UInt32(clamping: limits.streamWindow)),
                        HTTP2Setting(.maxHeaderListSize, UInt32(clamping: assembler.decoder.limits.maximumListSize))]
        if role == .server {
            settings.insert(HTTP2Setting(.maxConcurrentStreams, UInt32(clamping: limits.maximumConcurrentStreams)), at: 0)
        } else {
             
            settings.insert(HTTP2Setting(.enablePush, 0), at: 0)
            settings.insert(HTTP2Setting(.maxConcurrentStreams, 0), at: 1)
        }
        var preface = role == .client ? HTTP2Frame.clientPreface : Data()
        preface += frame(.settings(settings))
        if limits.connectionWindow > receiveWindow {
            if mayCredit {
                preface += frame(.windowUpdate(stream: 0, increment: UInt32(limits.connectionWindow - receiveWindow)))
                receiveWindow = limits.connectionWindow
            } else {
                pendingRaise = limits.connectionWindow - receiveWindow
                waitForBudget()
            }
        }
        queueControl(preface)
        flush()
        armIdle()
        receive()
    }

     

     
     
    func openStream(method: String) -> ModuleH2Stream? {
        dispatchPrecondition(condition: .onQueue(queue))
        guard canOpenStream else { return nil }
        let id = nextStream
        nextStream += 2
        let stream = ModuleH2Stream(id: id, connection: self, carrying: .response(toMethod: method),
                                    sendWindow: peerSettings.initialWindowSize, receiveWindow: limits.streamWindow)
        streams[id] = stream
        idleTimer?.cancel()
        idleTimer = nil
        return stream
    }

     
    func goAway(_ code: HTTP2ErrorCode = .noError, _ why: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !ended, !sentGoaway else { return }
        sentGoaway = true
        queueControl(frame(.goaway(lastStream: role == .server ? lastPeerStream : 0, code, debugData: Data(why.utf8.prefix(256)))))
        flush()
        if streams.isEmpty { finishAfterWriting(why) }
    }

     
    func close(_ why: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        end(why, notifyingStreams: true)
    }

     

    private func receive() {
        transport.receive(maximumLength: 64 * 1024) { [weak self] data, isComplete, error in
            guard let self, !self.ended, !self.readingFailed else { return }
            if let data, !data.isEmpty { self.reader.append(data) }
            if isComplete || error != nil {
                self.peerEnded = error.map { #"the connection ended: \#($0)"# } ?? #"the peer closed the connection"#
            }
            self.readOn()
        }
    }

     
     
     
     
    private func readOn() {
        readFrames()
        guard !ended, !readingFailed else { return }
        if backlogFull { return pauseReading() }
        if let why = peerEnded { return end(why, notifyingStreams: true) }
        receive()
    }

    private var backlogFull: Bool {
        control.count > ModuleH2Limits.maximumControlBacklogFrames || controlBytes > ModuleH2Limits.maximumControlBacklogBytes
    }

    private func pauseReading() {
        guard !readPaused else { return }
        readPaused = true
        backlogTimer = ModuleDeadline(after: limits.backlogTimeout, queue: queue) { [weak self] in
            guard let self, !self.ended, self.readPaused else { return }
            self.say(#"h2 connection with the \#(self.peerName) ends: it does not read what it is sent (\#(self.control.count) frames waiting for \#(self.limits.backlogTimeout) s)"#)
            self.calmDown(#"the peer does not read"#, now: true)
        }
    }

     
    private func resumeReadingIfDrained() {
        guard readPaused, !ended,
              control.count <= ModuleH2Limits.maximumControlBacklogFrames / 2,
              controlBytes <= ModuleH2Limits.maximumControlBacklogBytes / 2 else { return }
        readPaused = false
        backlogTimer?.cancel()
        backlogTimer = nil
        readOn()
    }

    private func readFrames() {
        while !ended, !readingFailed, !backlogFull {
            let frame: HTTP2Frame?
            do {
                 
                 
                 
                 
                reader.isBlockOpen = assembler.isBlockOpen
                frame = try reader.next()
            } catch let error as HTTP2Error {
                fail(error)
                continue
            } catch {
                return end(#"unreadable: \#(error)"#, notifyingStreams: true)
            }
            guard let frame else { return }
            do {
                let inbound = try assembler.take(frame)
                holdHeaderBlock()
                guard let inbound else { continue }
                try handle(inbound)
            } catch let error as HTTP2Error {
                holdHeaderBlock()
                fail(error)
            } catch {
                end(#"unreadable: \#(error)"#, notifyingStreams: true)
            }
        }
    }

     
     
     
    private func holdHeaderBlock() {
        guard let buffers else { return }
        let now = assembler.bufferedBytes
        guard now != headerHeld else { return }
        if now > headerHeld {
            buffers.hold(now - headerHeld, by: ObjectIdentifier(self))
        } else {
            buffers.release(headerHeld - now, by: ObjectIdentifier(self))
        }
        headerHeld = now
    }

    private var peerName: String { role == .server ? #"app"# : #"server"# }

    private func queueControl(_ bytes: Data) {
        control.append(bytes)
        controlBytes += bytes.count
    }

     
     
    private func calmDown(_ why: String, now: Bool = false) {
        guard !ended else { return }
        readingFailed = true
        if !sentGoaway {
            sentGoaway = true
            queueControl(frame(.goaway(lastStream: role == .server ? lastPeerStream : 0, .enhanceYourCalm,
                                       debugData: Data(why.utf8.prefix(256)))))
        }
        if now, writing { return end(why, notifyingStreams: true) }
        finishAfterWriting(why)
    }

     
     
    private func notePeerReset() {
        let now = DispatchTime.now().uptimeNanoseconds
        if resetsInWindow == 0 || Double(now &- resetWindowStart) / 1_000_000_000 > limits.peerResetWindow {
            resetWindowStart = now
            resetsInWindow = 0
        }
        resetsInWindow += 1
        guard resetsInWindow > limits.maximumPeerResets else { return }
        say(#"h2 connection with the \#(peerName) ends: it reset \#(resetsInWindow) streams within \#(limits.peerResetWindow) s"#)
        calmDown(#"too many streams reset"#)
    }

    private func handle(_ inbound: HTTP2Inbound) throws {
        switch inbound {
        case .headers(let block):
            try headers(block)
        case .pushPromise:
             
            throw HTTP2Error.connection(.protocolError, .pushPromiseRefused)
        case .frame(let frame):
            try handle(frame)
        }
    }

    private func handle(_ frame: HTTP2Frame) throws {
        switch frame {
        case .data(let data):
            try self.data(data)
        case .settings(let settings):
            apply(settings)
            queueControl(self.frame(.settingsAck))
            flush()
        case .settingsAck:
             
             
            break
        case .ping(let opaque, let ack):
            if !ack {
                queueControl(self.frame(.ping(opaque: opaque, ack: true)))
                flush()
            }
        case .goaway(let lastStream, let code, let debug):
            receivedGoaway = lastStream
            let said = String(decoding: debug.prefix(256), as: UTF8.self)
            say(#"h2 GOAWAY from the \#(role == .server ? "app" : "server"): \#(code.rawValue), last stream \#(lastStream)\#(said.isEmpty ? "" : ": " + said)"#)
            if role == .client {
                for (id, stream) in streams where id > lastStream { finish(stream, .refused, sendReset: false) }
            }
            if streams.isEmpty { finishAfterWriting(#"GOAWAY from the peer"#) }
        case .windowUpdate(let id, let increment):
            if id == 0 {
                guard sendWindow + Int(increment) <= Int(HTTP2Frame.largestWindowSize) else {
                    throw HTTP2Error.connection(.flowControlError, .badWindowIncrement(increment))
                }
                sendWindow += Int(increment)
            } else if let stream = streams[id] {
                guard stream.sendWindow + Int(increment) <= Int(HTTP2Frame.largestWindowSize) else {
                    throw HTTP2Error.stream(id, .flowControlError, .badWindowIncrement(increment))
                }
                stream.sendWindow += Int(increment)
                markReady(stream)
            }
            flush()
        case .rstStream(let id, let code):
            notePeerReset()
            guard !readingFailed else { return }
            if let stream = streams[id] {
                finish(stream, code == .refusedStream ? .refused : .reset(code), sendReset: false)
            } else if !closedSet.contains(id), isIdle(id) {
                 
                throw HTTP2Error.connection(.protocolError, .needsStream(.rstStream))
            }
        case .priority, .unknown:
             
            break
        case .headers, .continuation, .pushPromise:
             
            break
        }
    }

     
    private func isIdle(_ id: UInt32) -> Bool {
        role == .server ? id > lastPeerStream : id >= nextStream
    }

    private func headers(_ block: HTTP2HeaderBlock) throws {
        let id = block.stream
        if let stream = streams[id] {
            guard !stream.remoteEnded else { throw HTTP2Error.stream(id, .streamClosed, .afterEndStream) }
            let part = try stream.tracker.receive(block)
            if block.endStream { stream.remoteEnded = true }
            switch part {
            case .response(let head): stream.onResponse?(head)
            case .trailers(let trailers): stream.onTrailers?(trailers)
            case .request: break
            }
            if stream.remoteEnded { finishIfDone(stream) }
            return
        }
         
         
         
         
        if closedSet.contains(id) { return }
        if role == .client, !isIdle(id) { return }
        guard role == .server else {
             
            throw HTTP2Error.connection(.protocolError, .badStreamIdentifier)
        }
         
        guard id % 2 == 1, id > lastPeerStream else { throw HTTP2Error.connection(.protocolError, .badStreamIdentifier) }
        lastPeerStream = id
        if sentGoaway || receivedGoaway != nil || streams.count >= limits.maximumConcurrentStreams {
            queueControl(frame(.rstStream(stream: id, .refusedStream)))
            remember(id)
            return flush()
        }
        let stream = ModuleH2Stream(id: id, connection: self, carrying: .request, sendWindow: peerSettings.initialWindowSize,
                                    receiveWindow: limits.streamWindow)
        let part: HTTP2MessagePart
        do {
            part = try stream.tracker.receive(block)
        } catch let error as HTTP2Error {
            queueControl(frame(.rstStream(stream: id, error.code)))
            remember(id)
            say(#"h2 stream \#(id) from the app refused: \#(String(describing: error.fault))"#)
            return flush()
        }
        guard case .request(let head) = part else { return }
        streams[id] = stream
        if block.endStream { stream.remoteEnded = true }
        idleTimer?.cancel()
        idleTimer = nil
        onRequest?(stream, head)
    }

    private func data(_ data: HTTP2DataFrame) throws {
        let length = data.flowControlledLength
         
        guard length <= receiveWindow else { throw HTTP2Error.connection(.flowControlError, .frameTooLarge(length)) }
        receiveWindow -= length
        guard let stream = streams[data.stream] else {
             
            guard closedSet.contains(data.stream) || !isIdle(data.stream) else {
                throw HTTP2Error.connection(.protocolError, .needsStream(.data))
            }
            credit(connection: length, now: true)
            return
        }
        hold(length)
        guard !stream.remoteEnded else { throw HTTP2Error.stream(data.stream, .streamClosed, .afterEndStream) }
        guard length <= stream.receiveWindow else {
            throw HTTP2Error.stream(data.stream, .flowControlError, .frameTooLarge(length))
        }
        stream.receiveWindow -= length
        try stream.tracker.receive(data)
        if stream.creditsConnectionOnReceipt {
            stream.connectionCreditedAhead += length
            credit(connection: length, now: false)
        }
         
        let padding = length - data.payload.count
        if padding > 0 { consumed(padding, on: stream) }
        if data.endStream { stream.remoteEnded = true }
        stream.onData?(data.payload, data.endStream)
        if stream.remoteEnded { finishIfDone(stream) }
    }

    private func apply(_ settings: [HTTP2Setting]) {
        let before = peerSettings.initialWindowSize
        peerSettings.apply(settings)
        let delta = peerSettings.initialWindowSize - before
        if delta != 0 {
             
            for stream in streams.values {
                stream.sendWindow += delta
                markReady(stream)
            }
        }
        encoder.setPeerMaximumTableSize(peerSettings.headerTableSize)
        flush()
    }

     

    fileprivate func consumed(_ count: Int, on stream: ModuleH2Stream) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !ended, !stream.creditedAtEnd else { return }
        let open = !stream.over && !stream.remoteEnded
         
         
        if open { stream.uncredited += count }
        release(count)
        if open, stream.uncredited >= limits.streamWindow / 2 {
            if mayCredit { creditStream(stream) } else { waitForBudget() }
        }
        let ahead = min(count, stream.connectionCreditedAhead)
        stream.connectionCreditedAhead -= ahead
        credit(connection: count - ahead, now: false)
    }

    private func credit(connection count: Int, now: Bool) {
        uncredited += count
        if now || uncredited >= max(limits.connectionWindow, 65_535) / 2 {
            if mayCredit { creditConnection() } else { waitForBudget() }
        }
        flush()
    }

    private func creditStream(_ stream: ModuleH2Stream) {
        guard stream.uncredited > 0 else { return }
        queueControl(frame(.windowUpdate(stream: stream.id, increment: UInt32(stream.uncredited))))
        stream.receiveWindow += stream.uncredited
        stream.uncredited = 0
    }

    private func creditConnection() {
        guard uncredited > 0 else { return }
        queueControl(frame(.windowUpdate(stream: 0, increment: UInt32(uncredited))))
        receiveWindow += uncredited
        uncredited = 0
    }

     

    private var mayCredit: Bool { buffers?.allowsCredit(ObjectIdentifier(self), floor: limits.streamWindow) ?? true }

    private func hold(_ count: Int) {
        guard count > 0, let buffers else { return }
        heldHere += count
        buffers.hold(count, by: ObjectIdentifier(self))
    }

    private func release(_ count: Int) {
        guard let buffers else { return }
        let taken = min(count, heldHere)
        guard taken > 0 else { return }
        heldHere -= taken
        buffers.release(taken, by: ObjectIdentifier(self))
    }

    private func waitForBudget() {
        guard !creditsHeld, let buffers else { return }
        creditsHeld = true
        buffers.wait(ObjectIdentifier(self)) { [weak self] in self?.budgetFreed() }
    }

     
    private func budgetFreed() {
        guard creditsHeld, !ended else { return }
        creditsHeld = false
        guard mayCredit else { return waitForBudget() }
        uncredited += pendingRaise
        pendingRaise = 0
        for stream in streams.values where !stream.over && !stream.remoteEnded { creditStream(stream) }
        creditConnection()
        flush()
    }

     

    private func markReady(_ stream: ModuleH2Stream) {
        guard !stream.outbound.isEmpty, !ready.contains(stream.id) else { return }
        ready.append(stream.id)
    }

     
     
     
     
    fileprivate func flush() {
        guard !ended, !writing else { return }
        guard !flushing else {
            flushAgain = true
            return
        }
        flushing = true
         
         
         
         
        for stream in streams.values.sorted(by: { $0.id < $1.id }) where !stream.outbound.isEmpty { markReady(stream) }
        if role == .client { orderFirstHeads() }
        var batch = Data()
        var completions: [(Bool) -> Void] = []
        var done: [ModuleH2Stream] = []
        for bytes in control { batch += bytes }
        control.removeAll()
        controlBytes = 0
        let frameSize = max(Int(HTTP2Frame.defaultMaximumFrameSize), min(peerSettings.maxFrameSize, 64 * 1024))
         
        var turns = 0
        while !ready.isEmpty, batch.count < 256 * 1024, turns < 4096 {
            turns += 1
            let id = ready.removeFirst()
            guard let stream = streams[id], let item = stream.outbound.first else { continue }
            switch item {
            case .head(let fields, let endStream, let completion):
                if role == .client, !stream.headSent, id < highestOpened {
                     
                     
                    say(#"h2 stream \#(id) to the server could not open in order: refused here"#)
                    finish(stream, .refused, sendReset: false)
                    continue
                }
                stream.outbound.removeFirst()
                if role == .client, !stream.headSent { highestOpened = id }
                let block = encoder.encode(fields)
                batch += (try? HTTP2Serializer.headers(stream: id, block: block, endStream: endStream,
                                                        maximumFrameSize: peerSettings.maxFrameSize)) ?? Data()
                stream.headSent = true
                if let completion { completions.append(completion) }
            case .data(let data, let endStream, let completion):
                let room = min(sendWindow, stream.sendWindow, frameSize)
                guard room > 0 || data.isEmpty else { continue }
                let piece = data.prefix(max(0, room))
                let rest = data.dropFirst(piece.count)
                let last = rest.isEmpty
                batch += frame(.data(HTTP2DataFrame(stream: id, payload: Data(piece), endStream: last && endStream)))
                sendWindow -= piece.count
                stream.sendWindow -= piece.count
                if last {
                    stream.outbound.removeFirst()
                    if let completion { completions.append(completion) }
                } else {
                    stream.outbound[0] = .data(Data(rest), endStream: endStream, completion: completion)
                }
            }
            if !stream.outbound.isEmpty { markReady(stream) }
            if stream.outbound.isEmpty, stream.localEnded || stream.pendingReset != nil { done.append(stream) }
        }
        flushing = false
        guard !batch.isEmpty else {
            completions.forEach { $0(true) }
            done.forEach { doneSending($0) }
            if flushAgain {
                flushAgain = false
                flush()
            }
            return
        }
        writing = true
        flushAgain = false
        transport.send(batch) { [weak self] error in
            guard let self else { return }
            self.writing = false
            if let error {
                completions.forEach { $0(false) }
                return self.end(#"the connection could not be written: \#(error)"#, notifyingStreams: true)
            }
            completions.forEach { $0(true) }
            if self.closingAfterWrite, self.control.isEmpty, self.ready.isEmpty {
                return self.end(self.closingReason, notifyingStreams: true)
            }
            self.flush()
            self.resumeReadingIfDrained()
        }
         
         
        done.forEach { doneSending($0) }
    }

     
     
    private func orderFirstHeads() {
        let positions = ready.indices.filter { streams[ready[$0]]?.headSent == false }
        guard positions.count > 1 else { return }
        let ordered = positions.map { ready[$0] }.sorted()
        for (position, id) in zip(positions, ordered) { ready[position] = id }
    }

    private func frame(_ frame: HTTP2Frame) -> Data {
        (try? HTTP2Serializer.frame(frame, maximumFrameSize: max(peerSettings.maxFrameSize, Int(HTTP2Frame.defaultMaximumFrameSize))))
            ?? Data()
    }

     

    private func fail(_ error: HTTP2Error) {
        switch error {
        case .stream(let id, let code, let fault):
            say(#"h2 stream \#(id) reset (\#(code.rawValue)): \#(String(describing: fault))"#)
            if let stream = streams[id] {
                finish(stream, .resetHere(code), sendReset: true, code: code)
            } else {
                queueControl(frame(.rstStream(stream: id, code)))
                remember(id)
                flush()
            }
        case .connection(let code, let fault):
            readingFailed = true
            say(#"h2 connection with the \#(role == .server ? "app" : "server") ends (\#(code.rawValue)): \#(String(describing: fault))"#)
            if !sentGoaway {
                sentGoaway = true
                queueControl(frame(.goaway(lastStream: role == .server ? lastPeerStream : 0, code, debugData: Data())))
            }
            finishAfterWriting(String(describing: fault))
        }
    }

    fileprivate func reset(_ stream: ModuleH2Stream, _ code: HTTP2ErrorCode) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !stream.over else { return }
        finish(stream, .resetHere(code), sendReset: true, code: code)
    }

    fileprivate func resetAfterSending(_ stream: ModuleH2Stream, _ code: HTTP2ErrorCode) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !stream.over else { return }
        if stream.outbound.isEmpty { return reset(stream, code) }
        stream.pendingReset = code
    }

     
     
    private func doneSending(_ stream: ModuleH2Stream) {
        if let code = stream.pendingReset {
            stream.pendingReset = nil
            return reset(stream, code)
        }
        finishIfDone(stream)
    }

    private func finishIfDone(_ stream: ModuleH2Stream) {
        guard stream.localEnded, stream.remoteEnded, stream.outbound.isEmpty else { return }
        finish(stream, .finished, sendReset: false)
    }

    private func finish(_ stream: ModuleH2Stream, _ how: ModuleH2StreamEnd, sendReset: Bool, code: HTTP2ErrorCode = .cancel) {
        guard !stream.over else { return }
        stream.over = true
        streams[stream.id] = nil
        remember(stream.id)
        ready.removeAll { $0 == stream.id }
         
        let pending = stream.outbound
        stream.outbound.removeAll()
        if sendReset, role == .server || stream.headSent { queueControl(frame(.rstStream(stream: stream.id, code))) }
        let unconsumed = limits.streamWindow - stream.receiveWindow - stream.uncredited
        if unconsumed > 0, how != .finished {
            stream.creditedAtEnd = true
            release(unconsumed)
            credit(connection: max(0, unconsumed - stream.connectionCreditedAhead), now: false)
        }
        for item in pending { item.completion?(false) }
        let end = stream.onEnd
        stream.onEnd = nil
        stream.onData = nil
        stream.onResponse = nil
        stream.onTrailers = nil
        end?(how)
        onStreamClosed?()
        if streams.isEmpty {
            if sentGoaway || receivedGoaway != nil { finishAfterWriting(#"no stream left after GOAWAY"#) } else { armIdle() }
        }
        flush()
    }

    private func remember(_ id: UInt32) {
        guard closedSet.insert(id).inserted else { return }
        closed.append(id)
        if closed.count > limits.rememberedClosedStreams { closedSet.remove(closed.removeFirst()) }
    }

    private func armIdle() {
        guard idleTimer == nil, streams.isEmpty, !ended else { return }
        idleTimer = ModuleDeadline(after: limits.idleTimeout, queue: queue) { [weak self] in
            guard let self else { return }
            self.idleTimer = nil
            guard self.streams.isEmpty else { return }
            self.goAway(.noError, #"idle"#)
        }
    }

    private var closingAfterWrite = false
    private var closingReason = ""

     
    private func finishAfterWriting(_ why: String) {
        guard !ended else { return }
        closingAfterWrite = true
        closingReason = why
        if !writing { flush() }
        if !writing, control.isEmpty { end(why, notifyingStreams: true) }
    }

    private func end(_ why: String, notifyingStreams: Bool) {
        guard !ended else { return }
        ended = true
        idleTimer?.cancel()
        idleTimer = nil
        backlogTimer?.cancel()
        backlogTimer = nil
         
        if let buffers {
            buffers.forget(ObjectIdentifier(self), counted: heldHere + headerHeld)
            heldHere = 0
            headerHeld = 0
        }
        let open = Array(streams.values)
        streams.removeAll()
        ready.removeAll()
        transport.cancel()
        if notifyingStreams {
            for stream in open where !stream.over {
                stream.over = true
                for item in stream.outbound { item.completion?(false) }
                stream.outbound.removeAll()
                let end = stream.onEnd
                stream.onEnd = nil
                end?(.lost(why))
            }
        }
         
         
         
        for stream in open {
            stream.onEnd = nil
            stream.onData = nil
            stream.onResponse = nil
            stream.onTrailers = nil
        }
        let told = onEnd
        onEnd = nil
        onRequest = nil
        onStreamClosed = nil
        told?(why)
    }
}
#endif
