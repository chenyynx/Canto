#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 

 
final class ModuleH2StreamShared {
     
    let original: HTTP2RequestHead
     
     
    let synthesizedHost: String?
     
    var upstreamTrailers: HTTP2Trailers?
     
     
    var onRefused: (() -> Void)?
     
     
    var onUpstreamOpened: (() -> Void)?

    func upstreamOpened() {
        let told = onUpstreamOpened
        onUpstreamOpened = nil
        told?()
    }

    init(original: HTTP2RequestHead, synthesizedHost: String?) {
        self.original = original
        self.synthesizedHost = synthesizedHost
    }
}

enum ModuleH2Bridge {
     
     
     
    static func h1Request(_ head: HTTP2RequestHead, endStream: Bool) -> (head: ModuleHTTPRequestHead, bytes: Data, chunked: Bool)? {
        var fields: [ModuleHTTPField] = []
        if let authority = head.effectiveAuthority { fields.append(ModuleHTTPField(name: #"host"#, value: authority)) }
        var cookies: [String] = []
        var cookieAt: Int?
        for field in head.headers.fields {
            switch field.name {
            case #"host"#:
                 
                continue
            case #"cookie"#:
                if cookieAt == nil { cookieAt = fields.count }
                cookies.append(field.value)
            default:
                fields.append(field)
            }
        }
        if let cookieAt { fields.insert(ModuleHTTPField(name: #"cookie"#, value: cookies.joined(separator: "; ")), at: cookieAt) }
        var headers = ModuleHTTPHeaders(fields)
        let chunked = !endStream && !headers.contains(#"content-length"#)
        if chunked { headers.add(#"transfer-encoding"#, #"chunked"#) }
        let request = ModuleHTTPRequestHead(method: head.method, target: head.path ?? "/", version: .http11, headers: headers)
        guard let bytes = try? ModuleHTTPSerializer.head(request) else { return nil }
        return (request, bytes, chunked)
    }

     
     
     
     
     
    static func upstreamHead(_ request: ModuleHTTPRequestHead, shared: ModuleH2StreamShared, url: String,
                             say: (String) -> Void) -> HTTP2RequestHead {
        var headers = request.headers
        let host = headers.first(#"host"#).map(HTTP2FieldRules.trimmingOuterWhitespace)
        headers.remove(#"host"#)
        headers.remove(#"transfer-encoding"#)
        var out = shared.original
        out.method = request.method
        out.path = request.target
        if host == shared.synthesizedHost {
            if let came = shared.original.headers.fields.firstIndex(where: { $0.name == #"host"# }) {
                headers.fields.insert(shared.original.headers.fields[came], at: min(came, headers.fields.count))
            }
        } else if let host, isValidAuthority(host) {
            out.authority = host
            out.authorityAsItCame = nil
            out.hostAsItCame = nil
        } else {
            say(#"the rewritten Host \#(host.map { $0.debugDescription } ?? "(none)") of \#(url) is not a host and port: the request keeps :authority \#(shared.original.authority ?? "(none)")"#)
            if let came = shared.original.headers.first(#"host"#) {
                headers.fields.insert(ModuleHTTPField(name: #"host"#, value: came), at: 0)
            }
        }
        out.headers = headers
        return out
    }

     
     
     
    static func isValidAuthority(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 1024, !HTTP2FieldRules.hasForbiddenCharacter(value),
              !value.unicodeScalars.contains(where: { $0.value <= 0x20 || $0.value >= 0x7F || "/?#@\\".unicodeScalars.contains($0) })
        else { return false }
        return ModuleConnectTarget.parse(value, defaultPort: 443) != nil
    }

     
     
     
     
    static func h1Response(_ head: HTTP2ResponseHead, requestMethod: String, endStream: Bool)
        -> (bytes: Data, chunked: Bool, length: Int64?)? {
        var headers = head.headers
        var chunked = false
        var length: Int64?
        let bodiless = requestMethod == "HEAD" || (100..<200).contains(head.status) || head.status == 204 || head.status == 304
        if !bodiless {
            if endStream {
                headers.set(#"content-length"#, "0")
            } else if let declared = (try? ModuleHTTPFraming.contentLength(headers)) ?? nil {
                length = declared
            } else {
                headers.remove(#"content-length"#)
                headers.add(#"transfer-encoding"#, #"chunked"#)
                chunked = true
            }
        }
        let response = ModuleHTTPResponseHead(version: .http11, status: head.status, reason: ModuleExchange.reason(head.status),
                                              headers: headers)
        guard let bytes = try? ModuleHTTPSerializer.head(response) else { return nil }
        return (bytes, chunked, length)
    }

     
    static func lastChunk(_ trailers: ModuleHTTPHeaders?) -> Data {
        guard let trailers, !trailers.fields.isEmpty else { return ModuleHTTPSerializer.lastChunk }
        var out = Data("0\r\n".utf8)
        for field in trailers.fields {
            let line = "\(field.name): \(field.value)\r\n"
            out += line.data(using: .isoLatin1) ?? Data(line.utf8)
        }
        out += Data("\r\n".utf8)
        return out
    }

     
    static func h1Trailers(_ trailers: HTTP2Trailers) -> ModuleHTTPHeaders {
        ModuleHTTPHeaders(trailers.headers.fields.filter {
            !$0.name.isEmpty && $0.name.allSatisfy(ModuleHTTPParser.isTokenCharacter) && ModuleHTTPParser.isValidFieldText($0.value)
        })
    }
}

 
 
struct ModuleH1BodyDecoder {
    enum Failure: Error, Equatable {
        case malformedChunk
        case lineTooLong
        case trailersTooLarge
        case truncated
    }

    static let maximumLine = 4096
    static let maximumTrailerBytes = 32 * 1024

    private enum State: Equatable {
        case length(Int64)
        case size
        case data(Int64)
        case dataEnd(sawCR: Bool)
        case trailer
        case untilEnd
        case done
    }

    private var state: State
    private var line: [UInt8] = []
    private var trailerBytes = 0
    private(set) var trailers = ModuleHTTPHeaders()
    let chunked: Bool

     
    init?(_ framing: ModuleHTTPFraming) {
        switch framing {
        case .none: return nil
        case .length(let count): state = count == 0 ? .done : .length(count); chunked = false
        case .chunked: state = .size; chunked = true
        case .untilClose: state = .untilEnd; chunked = false
        }
    }

    var isComplete: Bool { state == .done }
     
    var readsUntilEnd: Bool { state == .untilEnd }

     
    mutating func consume(_ data: Data) throws -> (consumed: Int, payload: Data) {
        var payload = Data()
        var index = data.startIndex
        while index < data.endIndex {
            switch state {
            case .done:
                return (index - data.startIndex, payload)
            case .untilEnd:
                payload += data[index...]
                index = data.endIndex
            case .length(let remaining), .data(let remaining):
                let take = Int(min(remaining, Int64(data.endIndex - index)))
                payload += data[index..<(index + take)]
                index += take
                let left = remaining - Int64(take)
                if case .length = state {
                    state = left == 0 ? .done : .length(left)
                } else {
                    state = left == 0 ? .dataEnd(sawCR: false) : .data(left)
                }
            case .dataEnd(let sawCR):
                let byte = data[index]
                index += 1
                if !sawCR {
                    guard byte == 0x0D else { throw Failure.malformedChunk }
                    state = .dataEnd(sawCR: true)
                } else {
                    guard byte == 0x0A else { throw Failure.malformedChunk }
                    state = .size
                }
            case .size, .trailer:
                let byte = data[index]
                index += 1
                guard byte == 0x0A else {
                    line.append(byte)
                    guard line.count <= Self.maximumLine else { throw Failure.lineTooLong }
                    continue
                }
                if line.last == 0x0D { line.removeLast() }
                let text = line
                line = []
                if state == .size {
                    let size = try Self.size(text)
                    state = size == 0 ? .trailer : .data(size)
                } else if text.isEmpty {
                    state = .done
                } else {
                    trailerBytes += text.count
                    guard trailerBytes <= Self.maximumTrailerBytes else { throw Failure.trailersTooLarge }
                    guard let colon = text.firstIndex(of: 0x3A), colon > 0 else { throw Failure.malformedChunk }
                    let name = HPACKOctets.text(text[..<colon])
                    let value = HPACKOctets.text(text[(colon + 1)...]).trimmingCharacters(in: ModuleHTTPWhitespace.optional)
                    guard name.allSatisfy(ModuleHTTPParser.isTokenCharacter) else { throw Failure.malformedChunk }
                    trailers.add(name, value)
                }
            }
        }
        return (index - data.startIndex, payload)
    }

     
     
    mutating func endOfStream() throws {
        switch state {
        case .untilEnd, .done: state = .done
        default: throw Failure.truncated
        }
    }

    private static func size(_ line: [UInt8]) throws -> Int64 {
        var size: Int64 = 0
        var digits = 0
        for byte in line {
            let value: Int64
            switch byte {
            case 0x30...0x39: value = Int64(byte - 0x30)
            case 0x41...0x46: value = Int64(byte - 0x41 + 10)
            case 0x61...0x66: value = Int64(byte - 0x61 + 10)
            case 0x3B, 0x20, 0x09:
                 
                guard digits > 0 else { throw Failure.malformedChunk }
                return size
            default:
                throw Failure.malformedChunk
            }
            digits += 1
            guard digits <= 15 else { throw Failure.malformedChunk }
            size = size * 16 + value
        }
        guard digits > 0 else { throw Failure.malformedChunk }
        return size
    }
}

 
 
 
 
 
 
final class ModuleH2AppStream: ModuleStream {
    private let stream: ModuleH2Stream
    private let queue: DispatchQueue
    private let shared: ModuleH2StreamShared
    private let appMethod: String
    private let chunked: Bool
    private let url: String
    private let say: (String) -> Void
    private var items: [(bytes: Data, credit: Int)] = []
    private var requestEnded = false
    private var failure: Error?
    private var waiting: (maximum: Int, completion: (Data?, Bool, Error?) -> Void)?
    private var cancelled = false

    private enum Answer {
        case head
        case body(ModuleH1BodyDecoder)
        case done
    }

    private var answer = Answer.head
    private var answerBytes = Data()
    private var answerScan = ModuleHTTPHeadScan()
     
     
    private static let answerLimits = ModuleHTTPLimits(maximumHeadBytes: 256 * 1024, maximumStartLineBytes: 8 * 1024,
                                                       maximumFields: 512, maximumChunkLineBytes: 1024)

    private enum Out {
        case head([HPACKField], end: Bool)
        case data(Data, end: Bool)
    }

     
     
     
    init(_ stream: ModuleH2Stream, request: (head: ModuleHTTPRequestHead, bytes: Data, chunked: Bool), headEnded: Bool, url: String,
         shared: ModuleH2StreamShared, queue: DispatchQueue, say: @escaping (String) -> Void) {
        self.stream = stream
        self.queue = queue
        self.shared = shared
        self.url = url
        self.say = say
        appMethod = request.head.method
        chunked = request.chunked
        items.append((request.bytes, 0))
        requestEnded = headEnded
        stream.onData = { [weak self] data, end in self?.appSent(data, end: end) }
        stream.onTrailers = { [weak self] trailers in self?.appSentTrailers(trailers) }
        stream.onEnd = { [weak self] how in self?.streamEnded(how) }
    }

     

    func appSent(_ data: Data, end: Bool) {
        if !data.isEmpty { items.append((chunked ? ModuleHTTPSerializer.chunk(data) : data, data.count)) }
        if end { endRequest(nil) }
        deliver()
    }

    func appSentTrailers(_ trailers: HTTP2Trailers) {
        if !chunked, !trailers.headers.fields.isEmpty {
            say(#"the trailers of the request \#(url) are not sent on: its body has a Content-Length, which HTTP/1.1 gives no trailers"#)
        }
        endRequest(ModuleH2Bridge.h1Trailers(trailers))
        deliver()
    }

    private func endRequest(_ trailers: ModuleHTTPHeaders?) {
        guard !requestEnded else { return }
        requestEnded = true
        if chunked { items.append((ModuleH2Bridge.lastChunk(trailers), 0)) }
    }

    private func streamEnded(_ how: ModuleH2StreamEnd) {
        if how != .finished { failure = POSIXError(.ECONNRESET) }
        deliver()
    }

    func receive(maximumLength: Int, _ completion: @escaping (Data?, Bool, Error?) -> Void) {
        guard !cancelled else { return queue.async { completion(nil, true, POSIXError(.ECANCELED)) } }
        waiting = (max(1, maximumLength), completion)
        deliver()
    }

    private func deliver() {
        guard let (maximum, completion) = waiting else { return }
        if !items.isEmpty {
            waiting = nil
            var out = Data()
            var credit = 0
            while let first = items.first, out.count < maximum {
                let room = maximum - out.count
                if first.bytes.count <= room {
                    out += first.bytes
                    credit += first.credit
                    items.removeFirst()
                } else {
                    out += first.bytes.prefix(room)
                    items[0].bytes = Data(first.bytes.dropFirst(room))
                    break
                }
            }
            if credit > 0 { stream.consumed(credit) }
            return queue.async { completion(out, false, nil) }
        }
         
         
         
        guard let failure else { return }
        waiting = nil
        queue.async { completion(nil, true, failure) }
    }

     

    func send(_ data: Data, isFinal: Bool, _ completion: @escaping (Error?) -> Void) {
        guard !cancelled, !stream.isOver else { return queue.async { completion(POSIXError(.EPIPE)) } }
        answerBytes += data
        let outs: [Out]
        do {
            outs = try translate(isFinal: isFinal)
        } catch {
            say(#"the answer to \#(url) could not be written as HTTP/2: \#(error); the stream is reset"#)
            stream.reset(.internalError)
            return queue.async { completion(POSIXError(.EPIPE)) }
        }
        guard !outs.isEmpty else { return queue.async { completion(nil) } }
        for (index, out) in outs.enumerated() {
            let done: ((Bool) -> Void)? = index == outs.count - 1 ? { ok in completion(ok ? nil : POSIXError(.EPIPE)) } : nil
            switch out {
            case .head(let fields, let end): stream.sendHead(fields, endStream: end, completion: done)
            case .data(let data, let end): stream.sendData(data, endStream: end, completion: done)
            }
        }
    }

    private func translate(isFinal: Bool) throws -> [Out] {
        var outs: [Out] = []
        reading: while true {
            switch answer {
            case .head:
                switch try ModuleHTTPParser.response(answerBytes, limits: Self.answerLimits, scan: &answerScan) {
                case .needMore:
                    break reading
                case .head(let head, let consumed):
                    answerBytes = Data(answerBytes.dropFirst(consumed))
                    answerScan = ModuleHTTPHeadScan()
                    guard head.status != 101 else { throw ModuleHTTPError.malformedStartLine }
                    if head.isInterim {
                        outs.append(.head(try HTTP2ResponseHead(status: head.status, headers: head.headers).fields(), end: false))
                        continue
                    }
                    let framing = try ModuleHTTPFraming.ofResponse(head, requestMethod: appMethod)
                    var headers = head.headers
                    headers.remove(#"transfer-encoding"#)
                    if framing == .chunked || framing == .untilClose { headers.remove(#"content-length"#) }
                    let fields = try HTTP2ResponseHead(status: head.status, headers: headers).fields()
                    if let body = ModuleH1BodyDecoder(framing) {
                        outs.append(.head(fields, end: false))
                        answer = .body(body)
                    } else {
                        outs.append(.head(fields, end: true))
                        answer = .done
                    }
                }
            case .body(var body):
                let (consumed, payload) = try body.consume(answerBytes)
                answerBytes = Data(answerBytes.dropFirst(consumed))
                if !body.isComplete, isFinal, answerBytes.isEmpty {
                    try body.endOfStream()
                }
                if body.isComplete {
                    outs += try ending(payload, inBand: body.chunked ? body.trailers : nil)
                    answer = .done
                } else {
                    answer = .body(body)
                    if !payload.isEmpty { outs.append(.data(payload, end: false)) }
                    break reading
                }
            case .done:
                 
                answerBytes.removeAll()
                break reading
            }
        }
        return outs
    }

     
     
     
    private func ending(_ payload: Data, inBand: ModuleHTTPHeaders?) throws -> [Out] {
        let trailers = (inBand?.fields.isEmpty == false ? inBand : nil) ?? shared.upstreamTrailers?.headers
        guard let trailers, !trailers.fields.isEmpty else { return [.data(payload, end: true)] }
        var outs: [Out] = payload.isEmpty ? [] : [.data(payload, end: false)]
        outs.append(.head(try HTTP2Trailers(headers: trailers).fields(), end: true))
        return outs
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        let pending = waiting
        waiting = nil
        if let pending { queue.async { pending.completion(nil, true, POSIXError(.ECANCELED)) } }
        guard !stream.isOver else { return }
        if case .done = answer, stream.isLocalEnded {
             
            if !stream.isRemoteEnded { stream.reset(.noError) }
        } else {
            stream.reset(.cancel)
        }
    }
}

 
 
 
 
 
 
final class ModuleH2UpstreamEnd: ModuleStream {
    private let pool: ModuleH2UpstreamPool
    private let key: ModuleH2UpstreamPool.Key
    private let shared: ModuleH2StreamShared
    private let queue: DispatchQueue
    private let say: (String) -> Void

    private enum Request {
        case head
        case granting
        case body(ModuleH1BodyDecoder)
        case done
    }

    private var request = Request.head
     
    private var received = Data()
    private var unread = Data()
    private var scan = ModuleHTTPHeadScan()
    private var held: [(Error?) -> Void] = []
    private var method = "GET"
    private var url = ""
    private(set) var stream: ModuleH2Stream?
    private var raw: ModuleStream?
     
    private var ticket: ModuleH2UpstreamPool.Ticket?

    private var items: [(bytes: Data, credit: Int)] = []
    private var chunked = false
    private var lengthLeft: Int64?
    private var heldTail: (bytes: Data, credit: Int)?
    private var answered = false
    private var answerEnded = false
    private var failure: Error?
    private var waiting: (maximum: Int, completion: (Data?, Bool, Error?) -> Void)?
    private var cancelled = false

    init(pool: ModuleH2UpstreamPool, key: ModuleH2UpstreamPool.Key, shared: ModuleH2StreamShared, queue: DispatchQueue,
         say: @escaping (String) -> Void) {
        self.pool = pool
        self.key = key
        self.shared = shared
        self.queue = queue
        self.say = say
    }

     

    func send(_ data: Data, isFinal: Bool, _ completion: @escaping (Error?) -> Void) {
        guard !cancelled else { return queue.async { completion(POSIXError(.EPIPE)) } }
        if let raw { return raw.send(data, isFinal: isFinal, completion) }
        switch request {
        case .granting:
            received += data
            unread += data
            held.append(completion)
        case .head:
            received += data
            unread += data
            let parsed: ModuleHTTPParse<ModuleHTTPRequestHead>
            do {
                parsed = try ModuleHTTPParser.request(unread, limits: ModuleH2UpstreamEnd.requestLimits, scan: &scan)
            } catch {
                return fail(error, completion)
            }
            guard case .head(let head, let consumed) = parsed else { return queue.async { completion(nil) } }
            unread = Data(unread.dropFirst(consumed))
            let framing: ModuleHTTPFraming
            do {
                framing = try ModuleHTTPFraming.ofRequest(head)
            } catch {
                return fail(error, completion)
            }
            method = head.method
            url = "https://\(head.headers.first(#"host"#) ?? key.serverName)\(head.target)"
            let out = ModuleH2Bridge.upstreamHead(head, shared: shared, url: url, say: say)
            request = .granting
            held.append(completion)
            ticket = pool.request(key, method: head.method) { [self] result in granted(result, head: out, framing: framing) }
        case .body:
            unread += data
            pump([completion])
        case .done:
            queue.async { completion(nil) }
        }
    }

     
     
    private static let requestLimits = ModuleHTTPLimits(maximumHeadBytes: 64 * 1024, maximumStartLineBytes: 16 * 1024,
                                                        maximumFields: 256, maximumChunkLineBytes: 1024)

    private func fail(_ error: Error, _ completion: @escaping (Error?) -> Void) {
        say(#"the request for \#(key.serverName) could not be read for HTTP/2: \#(error)"#)
        failure = error
        queue.async { completion(POSIXError(.EPIPE)) }
        deliver()
    }

    private func granted(_ result: Result<ModuleH2UpstreamPool.Grant, ModuleUpstreamFailure>, head: HTTP2RequestHead,
                         framing: ModuleHTTPFraming) {
        ticket = nil
        if cancelled {
            if case .success(.h2(let stream)) = result { stream.reset(.cancel) }
            if case .success(.h1(let raw)) = result { raw.cancel() }
            return
        }
        if case .success = result { shared.upstreamOpened() }
        let completions = held
        held = []
        switch result {
        case .failure(let why):
            say(#"upstream \#(key.authority) (\#(key.serverName)) failed: \#(why)"#)
            failure = POSIXError(.ECONNREFUSED)
            for completion in completions { queue.async { completion(POSIXError(.EPIPE)) } }
            deliver()
        case .success(.h1(let raw)):
            self.raw = raw
            let bytes = received
            received = Data()
            unread = Data()
            raw.send(bytes) { error in completions.forEach { $0(error) } }
            if let pending = waiting {
                waiting = nil
                raw.receive(maximumLength: pending.maximum, pending.completion)
            }
        case .success(.h2(let stream)):
            self.stream = stream
            received = Data()
            stream.onResponse = { [weak self] head in self?.response(head) }
            stream.onData = { [weak self] data, end in self?.responseData(data, end: end) }
            stream.onTrailers = { [weak self] trailers in self?.responseTrailers(trailers) }
            stream.onEnd = { [weak self] how in self?.streamEnded(how) }
            let fields: [HPACKField]
            do {
                fields = try head.fields()
            } catch {
                say(#"the request \#(url) could not be written as HTTP/2: \#(error)"#)
                stream.reset(.cancel)
                failure = error
                for completion in completions { queue.async { completion(POSIXError(.EPIPE)) } }
                return deliver()
            }
            guard let body = ModuleH1BodyDecoder(framing) else {
                request = .done
                return stream.sendHead(fields, endStream: true) { ok in completions.forEach { $0(ok ? nil : POSIXError(.EPIPE)) } }
            }
            request = .body(body)
            stream.sendHead(fields, endStream: false)
            pump(completions)
        }
    }

    private func pump(_ completions: [(Error?) -> Void]) {
        guard case .body(var body) = request, let stream else { return completions.forEach { $0(nil) } }
        let finish: (Bool) -> Void = { ok in completions.forEach { $0(ok ? nil : POSIXError(.EPIPE)) } }
        let consumed: Int
        let payload: Data
        do {
            (consumed, payload) = try body.consume(unread)
        } catch {
            say(#"the request body of \#(url) could not be read: \#(error); its stream is reset"#)
            stream.reset(.cancel)
            return finish(false)
        }
        unread = Data(unread.dropFirst(consumed))
        guard body.isComplete else {
            request = .body(body)
            guard !payload.isEmpty else { return finish(true) }
            return stream.sendData(payload, endStream: false, completion: finish)
        }
        request = .done
        let trailers = body.chunked ? body.trailers : ModuleHTTPHeaders()
        guard !trailers.fields.isEmpty, let fields = try? HTTP2Trailers(headers: trailers).fields() else {
            return stream.sendData(payload, endStream: true, completion: finish)
        }
        if !payload.isEmpty { stream.sendData(payload, endStream: false) }
        stream.sendTrailers(fields, completion: finish)
    }

     

    private func response(_ head: HTTP2ResponseHead) {
        guard let stream else { return }
        guard let written = ModuleH2Bridge.h1Response(head, requestMethod: method, endStream: stream.isRemoteEnded) else {
            say(#"the answer to \#(url) could not be written as HTTP/1.1 for its rules: its stream is reset"#)
            stream.reset(.internalError)
            return
        }
        items.append((written.bytes, 0))
        if !head.isInterim {
            answered = true
            chunked = written.chunked
            lengthLeft = written.length
            if stream.isRemoteEnded { answerEnded = true }
        }
        deliver()
    }

    private func responseData(_ data: Data, end: Bool) {
        if chunked {
            if !data.isEmpty { items.append((ModuleHTTPSerializer.chunk(data), data.count)) }
            if end { items.append((ModuleHTTPSerializer.lastChunk, 0)) }
        } else if let left = lengthLeft, !end, Int64(data.count) >= left, !data.isEmpty {
             
             
            if let tail = heldTail { items.append(tail) }
            heldTail = (data, data.count)
            lengthLeft = 0
        } else {
            if let left = lengthLeft { lengthLeft = left - Int64(data.count) }
            if !data.isEmpty { items.append((data, data.count)) }
        }
        if end { endAnswer() }
        deliver()
    }

    private func responseTrailers(_ trailers: HTTP2Trailers) {
        shared.upstreamTrailers = trailers
        if chunked { items.append((ModuleH2Bridge.lastChunk(ModuleH2Bridge.h1Trailers(trailers)), 0)) }
        endAnswer()
        deliver()
    }

    private func endAnswer() {
        if let tail = heldTail {
            items.append(tail)
            heldTail = nil
        }
        answerEnded = true
    }

    private func streamEnded(_ how: ModuleH2StreamEnd) {
        switch how {
        case .finished:
            endAnswer()
        case .refused where !answered:
             
            failure = POSIXError(.ECONNRESET)
            let refused = shared.onRefused
            shared.onRefused = nil
            refused?()
        default:
            failure = POSIXError(.ECONNRESET)
        }
        deliver()
    }

    func receive(maximumLength: Int, _ completion: @escaping (Data?, Bool, Error?) -> Void) {
        if let raw { return raw.receive(maximumLength: maximumLength, completion) }
        guard !cancelled else { return queue.async { completion(nil, true, POSIXError(.ECANCELED)) } }
        waiting = (max(1, maximumLength), completion)
        deliver()
    }

    private func deliver() {
        guard let (maximum, completion) = waiting else { return }
        if !items.isEmpty {
            waiting = nil
            var out = Data()
            var credit = 0
            while let first = items.first, out.count < maximum {
                let room = maximum - out.count
                if first.bytes.count <= room {
                    out += first.bytes
                    credit += first.credit
                    items.removeFirst()
                } else {
                    out += first.bytes.prefix(room)
                    items[0].bytes = Data(first.bytes.dropFirst(room))
                    break
                }
            }
            if credit > 0 { stream?.consumed(credit) }
            return queue.async { completion(out, false, nil) }
        }
        if let failure {
            waiting = nil
            return queue.async { completion(nil, true, failure) }
        }
        if answerEnded {
            waiting = nil
            queue.async { completion(nil, true, nil) }
        }
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        ticket?.cancel()
        ticket = nil
        raw?.cancel()
        let pending = waiting
        waiting = nil
        if let pending { queue.async { pending.completion(nil, true, POSIXError(.ECANCELED)) } }
        let completions = held
        held = []
        for completion in completions { queue.async { completion(POSIXError(.EPIPE)) } }
        if let stream, !stream.isOver { stream.reset(.cancel) }
    }
}
#endif
