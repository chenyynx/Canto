#if os(iOS)
import Foundation
import Network
import Security
import UIKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ModuleCertificateProfileServer: @unchecked Sendable {
     
    enum Stop: Equatable, Sendable {
        case fetched
        case timedOut
        case backgroundTimeEnded
        case closed
        case failed(String)
    }

     
     
    struct BackgroundTime: Sendable {
        var begin: @MainActor @Sendable (_ expired: @escaping @Sendable () -> Void) -> Int
        var end: @Sendable (Int) -> Void

        static let app = BackgroundTime(
            begin: { expired in
                UIApplication.shared.beginBackgroundTask(withName: "modules.certificate.profile") { expired() }.rawValue
            },
            end: { task in
                DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: task)) }
            })

        static let none = BackgroundTime(begin: { _ in 0 }, end: { _ in })
    }

     
    static let lifetime: TimeInterval = 60
     
    static let startTimeout: TimeInterval = 5
     
     
    static let grace: TimeInterval = 5
     
    static let maximumRequestBytes = 8 * 1024

    let token: String
    private let profile: Data
    private let page: Data
    private let lifetime: TimeInterval
    private let grace: TimeInterval
    private let background: BackgroundTime
    private let queue: DispatchQueue
    private let log: @Sendable (String) -> Void
    private let fetched: @Sendable () -> Void
    private let stopped: @Sendable (Stop) -> Void

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var backgroundTask: Int?
    private var lifetimeTimer: DispatchWorkItem?
    private var graceTimer: DispatchWorkItem?
    private var handedOut = false
     
    private(set) var ended: Stop?
    private var port: UInt16?

     
     
    init(profile: Data, page: (_ profilePath: String) -> Data, lifetime: TimeInterval = ModuleCertificateProfileServer.lifetime,
         grace: TimeInterval = ModuleCertificateProfileServer.grace, background: BackgroundTime = .app,
         queue: DispatchQueue = DispatchQueue(label: "modules.certificate.profile", qos: .userInitiated),
         log: @escaping @Sendable (String) -> Void = { ClashLogStore.shared.append($0, stream: .app) },
         fetched: @escaping @Sendable () -> Void = {}, stopped: @escaping @Sendable (Stop) -> Void = { _ in }) {
        token = Self.newToken()
        self.profile = profile
        self.page = page(Self.profilePath(token: token))
        self.lifetime = lifetime
        self.grace = grace
        self.background = background
        self.queue = queue
        self.log = log
        self.fetched = fetched
        self.stopped = stopped
    }

    deinit {
        listener?.cancel()
        for connection in connections.values { connection.cancel() }
    }

    static func profilePath(token: String) -> String {
        "/\(token)/" + ModuleEngineLocations.certificateProfileName
    }

     
     
    var pageURL: URL? {
        queue.sync { port.flatMap { ended == nil ? URL(string: "http://127.0.0.1:\($0)/\(token)/") : nil } }
    }

     
    var profileURL: URL? {
        queue.sync { port.flatMap { ended == nil ? URL(string: "http://127.0.0.1:\($0)" + Self.profilePath(token: token)) : nil } }
    }

    var isListening: Bool { queue.sync { listener != nil && ended == nil } }

     
     
     
     
    @MainActor
    func start() async throws -> URL {
        let task = background.begin { [weak self] in
            self?.queue.async { self?.finish(.backgroundTimeEnded) }
        }
        queue.async { [self] in
            if ended == nil { backgroundTask = task } else { background.end(task) }
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            queue.async { [self] in
                guard listener == nil, ended == nil else {
                    return continuation.resume(throwing: Self.failure)
                }
                 
                 
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                let made: NWListener
                do {
                    made = try NWListener(using: parameters)
                } catch {
                    finish(.failed("\(error)"))
                    return continuation.resume(throwing: Self.failure)
                }
                listener = made
                var answered = false
                made.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                made.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !answered, let port = made.port?.rawValue else { return }
                        answered = true
                        self.port = port
                        self.armLimits()
                        self.log(#"modules: the certificate's profile is served on 127.0.0.1:\#(port) for one install"#)
                        continuation.resume(returning: URL(string: "http://127.0.0.1:\(port)/\(self.token)/")!)
                    case .failed(let error):
                        self.finish(.failed("\(error)"))
                        if !answered {
                            answered = true
                            continuation.resume(throwing: Self.failure)
                        }
                    case .cancelled:
                        if !answered {
                            answered = true
                            continuation.resume(throwing: Self.failure)
                        }
                    default:
                        break
                    }
                }
                made.start(queue: queue)
                queue.asyncAfter(deadline: .now() + Self.startTimeout) { [weak self] in
                    guard let self, !answered else { return }
                    answered = true
                    self.finish(.failed("not ready after \(Int(Self.startTimeout)) s"))
                    continuation.resume(throwing: Self.failure)
                }
            }
        }
    }

     
    func stop(_ why: Stop) {
        queue.async { [self] in finish(why) }
    }

     
     
    static var failure: AuthoredError { AuthoredError(text: ModulePageSnapshotBuilder.Copy.certificatePageUnavailable) }

     

    private func armLimits() {
        let timer = DispatchWorkItem { [weak self] in self?.finish(.timedOut) }
        lifetimeTimer = timer
        queue.asyncAfter(deadline: .now() + lifetime, execute: timer)
    }

    private func finish(_ why: Stop) {
        guard ended == nil else { return }
        ended = why
        lifetimeTimer?.cancel()
        graceTimer?.cancel()
        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections = [:]
        if let task = backgroundTask {
            backgroundTask = nil
            background.end(task)
        }
        log(#"modules: the certificate's profile is no longer served (\#(why))"#)
        stopped(why)
    }

    private func accept(_ connection: NWConnection) {
        guard ended == nil else { return connection.cancel() }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.connections[id] = nil
            default: break
            }
        }
        connection.start(queue: queue)
        read(connection, Data())
    }

    private func read(_ connection: NWConnection, _ buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumRequestBytes) { [weak self] data, _, isComplete, error in
            guard let self, self.ended == nil else { return connection.cancel() }
            var request = buffered
            if let data { request.append(data) }
            if let head = request.range(of: Data("\r\n\r\n".utf8)) {
                return self.answer(connection, head: request[request.startIndex..<head.lowerBound])
            }
            guard error == nil, !isComplete, request.count < Self.maximumRequestBytes else { return connection.cancel() }
            self.read(connection, request)
        }
    }

     
     
    private func answer(_ connection: NWConnection, head: Data) {
        let line = String(decoding: head.prefix { $0 != 0x0D && $0 != 0x0A }, as: UTF8.self).split(separator: " ")
        let method = line.first.map(String.init) ?? ""
        var path = line.count > 1 ? String(line[1]) : ""
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        let status: Int, type: String?, body: Data, isProfile: Bool
        switch (method, path) {
        case ("GET", Self.profilePath(token: token)), ("HEAD", Self.profilePath(token: token)):
            (status, type, body, isProfile) = (200, "application/x-apple-aspen-config", profile, true)
        case ("GET", "/\(token)/"), ("GET", "/\(token)"), ("HEAD", "/\(token)/"), ("HEAD", "/\(token)"):
            (status, type, body, isProfile) = (200, #"text/html; charset=utf-8"#, page, false)
        case ("GET", _), ("HEAD", _):
            (status, type, body, isProfile) = (404, nil, Data(), false)
        default:
            (status, type, body, isProfile) = (405, nil, Data(), false)
        }
        var headers = ["HTTP/1.1 \(status) \(Self.reason(status))"]
        if let type { headers.append("Content-Type: \(type)") }
        headers += ["Content-Length: \(body.count)", #"Cache-Control: no-store"#, #"Connection: close"#]
        if isProfile {
            headers.append("Content-Disposition: attachment; filename=\"\(ModuleEngineLocations.certificateProfileName)\"")
        }
        let sent = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + (method == "HEAD" ? Data() : body)
        let handsOut = isProfile && method == "GET"
        connection.send(content: sent, isComplete: true, completion: .contentProcessed { [weak self] error in
            connection.cancel()
            guard let self, handsOut, error == nil else { return }
            self.handedOutOnce()
        })
    }

     
     
    private func handedOutOnce() {
        guard !handedOut, ended == nil else { return }
        handedOut = true
        log(#"modules: the certificate's profile was handed out from 127.0.0.1"#)
        fetched()
        let timer = DispatchWorkItem { [weak self] in self?.finish(.fetched) }
        graceTimer = timer
        queue.asyncAfter(deadline: .now() + grace, execute: timer)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 404: return #"Not Found"#
        default: return #"Method Not Allowed"#
        }
    }

     
     
    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
