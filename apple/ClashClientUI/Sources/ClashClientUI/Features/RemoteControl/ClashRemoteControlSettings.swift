import Foundation

 
 
 
 
 
 
 
 

 
public struct ClashRemoteControlSettings: Codable, Equatable, Sendable {
     
    public static let defaultsKey = "core.remote-control"

    public enum Mode: String, Codable, Equatable, Sendable, CaseIterable {
         
        case configuration = "config"
         
        case thisDevice = "local"
         
        case localNetwork = "lan"

         
         
        public static func choices(hasLocalConsumers: Bool) -> [Mode] {
            hasLocalConsumers ? [.configuration, .thisDevice, .localNetwork] : [.configuration, .localNetwork]
        }

         
        public var title: ClashDisplayText {
            switch self {
            case .configuration: return .copy("Use Configuration")
            case .thisDevice: return .copy("This Device")
            case .localNetwork: return .copy("Local Network")
            }
        }
    }

    public enum PortProblem: Equatable, Sendable {
        case outOfRange
        case same
    }

    public var mode: Mode
    public var httpPort: Int
    public var tlsPort: Int
    public var secret: String
    public var certificatePEM: String
    public var privateKeyPEM: String
     
    public var fingerprint: String
     
    public var generation: Int

    public static let `default` = ClashRemoteControlSettings(
        mode: .configuration, httpPort: 9090, tlsPort: 9443,
        secret: "", certificatePEM: "", privateKeyPEM: "", fingerprint: "", generation: 0
    )

    public init(
        mode: Mode, httpPort: Int, tlsPort: Int, secret: String,
        certificatePEM: String, privateKeyPEM: String, fingerprint: String, generation: Int
    ) {
        self.mode = mode
        self.httpPort = httpPort
        self.tlsPort = tlsPort
        self.secret = secret
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
        self.fingerprint = fingerprint
        self.generation = generation
    }

     

     
    public static func load(from defaults: UserDefaults?) -> Self {
        guard let text = defaults?.string(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: Data(text.utf8))
        else { return .default }
        return value
    }

    public func save(to defaults: UserDefaults?) {
        defaults?.set(coreJSON, forKey: Self.defaultsKey)
    }

     
    public var coreJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

     

     
     
    public mutating func select(_ mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        if mode != .configuration, secret.isEmpty { secret = Self.mintSecret() }
        generation += 1
    }

    public mutating func regenerateSecret() {
        secret = Self.mintSecret()
        generation += 1
    }

     
     
     
     
     
    @discardableResult
    public mutating func select(_ mode: Mode, certificate: () -> String) -> String? {
        guard mode != self.mode else { return nil }
        var next = self
        next.mode = mode
        if mode != .configuration, next.secret.isEmpty { next.secret = Self.mintSecret() }
        if next.needsCertificate {
            if let error = next.adoptCertificate(json: certificate()) { return error }
            next.generation -= 1   
        }
        next.generation += 1
        self = next
        return nil
    }

     
    public var needsCertificate: Bool {
        mode == .localNetwork && (certificatePEM.isEmpty || privateKeyPEM.isEmpty)
    }

     
     
    @discardableResult
    public mutating func adoptCertificate(json: String) -> String? {
        struct Answer: Decodable {
            let certificatePEM: String?
            let privateKeyPEM: String?
            let fingerprint: String?
            let error: String?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: Data(json.utf8)) else {
            return json
        }
        if let error = answer.error, !error.isEmpty { return error }
        guard let certificate = answer.certificatePEM, !certificate.isEmpty,
              let key = answer.privateKeyPEM, !key.isEmpty
        else { return json }
        certificatePEM = certificate
        privateKeyPEM = key
        fingerprint = answer.fingerprint ?? ""
        generation += 1
        return nil
    }

     
    public var portProblem: PortProblem? {
        let range = 1024...65_535
        guard range.contains(httpPort), range.contains(tlsPort) else { return .outOfRange }
        return httpPort == tlsPort ? .same : nil
    }

    private static func mintSecret() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }
}

 
public struct ClashRemoteControlStatus: Equatable, Sendable {
    public struct Listener: Equatable, Sendable {
        public let address: String
         
        public let error: String?
        public let fingerprint: String?
    }

    public let generation: Int
    public let mode: ClashRemoteControlSettings.Mode?
     
    public let running: Bool
     
    public let rejection: String?
    public let http: Listener?
    public let tls: Listener?

    public init?(json: String) {
        struct Wire: Decodable {
            struct Slot: Decodable {
                let address: String?
                let error: String?
                let fingerprint: String?
            }
            let generation: Int?
            let mode: String?
            let running: Bool?
            let error: String?
            let http: Slot?
            let tls: Slot?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else { return nil }
        func listener(_ slot: Wire.Slot?) -> Listener? {
            guard let slot, let address = slot.address, !address.isEmpty else { return nil }
            return Listener(address: address, error: slot.error.flatMap { $0.isEmpty ? nil : $0 },
                            fingerprint: slot.fingerprint.flatMap { $0.isEmpty ? nil : $0 })
        }
        generation = wire.generation ?? 0
        mode = wire.mode.flatMap(ClashRemoteControlSettings.Mode.init(rawValue:))
        running = wire.running ?? false
        rejection = wire.error.flatMap { $0.isEmpty ? nil : $0 }
        http = listener(wire.http)
        tls = listener(wire.tls)
    }
}

 
public enum ClashRemoteControlPresentation {
     
    public static func addressLines(for settings: ClashRemoteControlSettings, hosts: [String]) -> [String] {
        switch settings.mode {
        case .configuration:
            return []
        case .thisDevice:
            return ["http://127.0.0.1:\(settings.httpPort)"]
        case .localNetwork:
            return hosts.map { "https://\($0):\(settings.tlsPort)" }
        }
    }

     
     
     
     
     
     
     
    public static func command(for settings: ClashRemoteControlSettings, host: String?) -> String {
        if settings.mode == .localNetwork, let host {
            return "export CLASH_API=\(quoted("https://\(host):\(settings.tlsPort)")) CLASH_SECRET=\(quoted(settings.secret)) "
                + "CLASH_FINGERPRINT=\(quoted(settings.fingerprint)); clash-cli status"
        }
        return "unset CLASH_FINGERPRINT; export CLASH_API=\(quoted("http://127.0.0.1:\(settings.httpPort)")) "
            + "CLASH_SECRET=\(quoted(settings.secret)); clash-cli status"
    }

     
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

     
     
    public static func installCommand(toolPath: String) -> String {
        "sudo mkdir -p /usr/local/bin && sudo ln -sf '\(toolPath)' /usr/local/bin/clash-cli"
    }
}
