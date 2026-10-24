#if os(iOS) || os(macOS)
import Foundation

 
 
 
 

 
 
enum ModuleScriptPhase: String, Codable, Equatable, Sendable {
    case request
    case response

     
    var scriptType: String { self == .request ? "http-request" : "http-response" }
}

 
 
 
 
enum ModuleScriptFamily: String, CaseIterable, Codable, Equatable, Sendable {
    case surge
    case shadowrocket
    case loon
    case stash
     
     
     
    case quantumultX
}

 
 
enum ModuleScriptKind: Equatable, Sendable {
     
     
    case http(ModuleScriptPhase)
     
    case cron
     
     
    case event(String)
     
     
    case networkChanged
     
    case generic

     
    var phase: ModuleScriptPhase? {
        if case .http(let phase) = self { return phase }
        return nil
    }

     
     
     
     
    func scriptType(in family: ModuleScriptFamily) -> String {
        switch self {
        case .http(let phase): return family == .stash ? phase.rawValue : phase.scriptType
        case .cron: return "cron"
        case .event: return "event"
        case .networkChanged: return family == .loon ? "network-changed" : "event"
        case .generic: return "generic"
        }
    }
}

 
 
enum ModuleScriptSyntax: String, Codable, Equatable, Sendable {
     
     
    case classic
     
    case loon351
}

 
enum ModuleScriptDefaults {
     
     
     
     
     
     
     
     
     
     
    static func timeoutSeconds(family: ModuleScriptFamily, kind: ModuleScriptKind, syntax: ModuleScriptSyntax) -> Double {
        if family == .quantumultX { return kind.phase != nil ? quantumultXHTTPSeconds : 300 }
        guard family == .loon else { return 5 }
        guard kind.phase != nil else { return 300 }
        switch syntax {
        case .classic: return 10
        case .loon351: return 20
        }
    }

     
     
    static let quantumultXHTTPSeconds: Double = 10
}

 
 
 
 
 
 
 
 
enum ModuleScriptArgument: Equatable, Sendable, ExpressibleByStringLiteral {
    case text(String)
    case object([Field])

     
    struct Field: Equatable, Sendable {
        var name: String
        var value: Value
    }

     
     
     
    enum Value: Equatable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
    }

     
    init(stringLiteral value: String) {
        self = .text(value)
    }
}

 
 
 
 
 
 
 
 
 
 
struct ModuleScriptLimitsTable: Equatable, Sendable {
     
     
    struct Host: Equatable, Sendable {
         
        var maximumRunning: Int
        var maximumWaiting: Int
        var maximumHTTPTimeout: Double
         
        var maximumAppTimeout: Double
         
        var idleTrimAfter: Double
        var sourceCacheBytes: Int
        var maximumSourceBytes: Int
         
         
         
         
        var footprintAllowanceBytes: Int64?
         
         
         
        var maximumNetworkBytesInFlight: Int
    }

     
    struct Run: Equatable, Sendable {
         
        var maximumTimers: Int
        var maximumNotifications: Int
         
        var ungzipOutputBytes: Int
         
        var maximumPendingRequests: Int
         
         
        var maximumWaitingRequests: Int
         
        var maximumRequestBodyBytes: Int
         
         
        var maximumResponseBodyBytes: Int
         
        var maximumRedirects = 5
         
         
         
        var maximumDOMSourceBytes: Int? = nil
    }

    var tunnel: Host
    var app: Host
    var tunnelRun: Run
    var appRun: Run
     
    var storeValueBytes: Int
    var storeTotalBytes: Int

     
     
     
     
     
     
     
     
     
     
    static let iOS = ModuleScriptLimitsTable(
        tunnel: Host(maximumRunning: 2, maximumWaiting: 16, maximumHTTPTimeout: 30, maximumAppTimeout: 600,
                     idleTrimAfter: 30, sourceCacheBytes: 1 << 20, maximumSourceBytes: 1 << 20,
                     footprintAllowanceBytes: nil, maximumNetworkBytesInFlight: 4 << 20),
        app: appHost,
        tunnelRun: Run(maximumTimers: 64, maximumNotifications: 8, ungzipOutputBytes: 1 << 20,
                       maximumPendingRequests: 4, maximumWaitingRequests: 8, maximumRequestBodyBytes: 256 << 10,
                       maximumResponseBodyBytes: 1 << 20, maximumDOMSourceBytes: 128 << 10),
        appRun: Run(maximumTimers: 64, maximumNotifications: 8, ungzipOutputBytes: 1 << 20,
                    maximumPendingRequests: 16, maximumWaitingRequests: 32, maximumRequestBodyBytes: 4 << 20,
                    maximumResponseBodyBytes: 8 << 20),
        storeValueBytes: 256 << 10, storeTotalBytes: 1 << 20)

     
    static let macOS = ModuleScriptLimitsTable(
        tunnel: Host(maximumRunning: 2, maximumWaiting: 32, maximumHTTPTimeout: 30, maximumAppTimeout: 600,
                     idleTrimAfter: 120, sourceCacheBytes: 8 << 20, maximumSourceBytes: 8 << 20,
                     footprintAllowanceBytes: nil, maximumNetworkBytesInFlight: 64 << 20),
        app: appHost,
        tunnelRun: Run(maximumTimers: 64, maximumNotifications: 8, ungzipOutputBytes: 16 << 20,
                       maximumPendingRequests: 16, maximumWaitingRequests: 64, maximumRequestBodyBytes: 16 << 20,
                       maximumResponseBodyBytes: 16 << 20),
        appRun: Run(maximumTimers: 64, maximumNotifications: 8, ungzipOutputBytes: 16 << 20,
                    maximumPendingRequests: 32, maximumWaitingRequests: 64, maximumRequestBodyBytes: 16 << 20,
                    maximumResponseBodyBytes: 16 << 20),
        storeValueBytes: 4 << 20, storeTotalBytes: 16 << 20)

     
     
     
    private static let appHost = Host(maximumRunning: 2, maximumWaiting: 32, maximumHTTPTimeout: 30, maximumAppTimeout: 600,
                                      idleTrimAfter: 60, sourceCacheBytes: 8 << 20, maximumSourceBytes: 8 << 20,
                                      footprintAllowanceBytes: nil, maximumNetworkBytesInFlight: 64 << 20)

    static var current: ModuleScriptLimitsTable {
#if os(macOS)
        return .macOS
#else
        return .iOS
#endif
    }
}

 
 
 
 
struct ModuleScriptDeclaration: Equatable, Sendable {
    var name: String
    var kind: ModuleScriptKind
    var family: ModuleScriptFamily
    var syntax: ModuleScriptSyntax
     
     
     
    var scriptPath: String
     
    var sourceFile: URL
     
    var sourceSHA256: String
    var requiresBody: Bool
    var binaryBodyMode: Bool
     
     
    var timeout: Double?
     
     
     
    var argument: ModuleScriptArgument?
     
     
     
     
     
    var environmentParameters: String? = nil
     
     
     
    var trigger: String? = nil

     
    var phase: ModuleScriptPhase? { kind.phase }

     
    var timeoutSeconds: Double {
        timeout ?? ModuleScriptDefaults.timeoutSeconds(family: family, kind: kind, syntax: syntax)
    }
}

struct ModuleScriptHeader: Codable, Equatable, Hashable, Sendable {
    var name: String
    var value: String
}

struct ModuleScriptHostRequest: Equatable, Sendable {
     
     
    var id: String
    var url: String
    var method: String
    var headers: [ModuleScriptHeader]
}

struct ModuleScriptHostResponse: Equatable, Sendable {
    var status: Int
    var headers: [ModuleScriptHeader]
}

 
struct ModuleScriptEdit: Equatable, Sendable {
    var url: String?
    var status: Int?
     
    var headers: [ModuleScriptHeader]?
    var body: Data?

    init(url: String? = nil, status: Int? = nil, headers: [ModuleScriptHeader]? = nil, body: Data? = nil) {
        self.url = url
        self.status = status
        self.headers = headers
        self.body = body
    }

    var isEmpty: Bool { url == nil && status == nil && headers == nil && body == nil }
}

 
enum ModuleScriptResult: Equatable, Sendable {
     
     
    case passThrough
     
     
    case modifyRequest(ModuleScriptEdit)
     
     
    case respond(ModuleScriptEdit)
     
    case modifyResponse(ModuleScriptEdit)
     
     
    case closeConnection
     
     
     
     
    case completed(json: String?)
}

 
enum ModuleScriptStopReason: Equatable, Sendable {
     
     
    case javaScriptUnavailable(String)
     
     
    case footprint(overBaselineBytes: Int64, allowanceBytes: Int64)
     
     
     
     
    case overran(scriptName: String, sha256: String, seconds: Double)
     
    case engine(String)
}

enum ModuleScriptSkipReason: Equatable, Sendable {
    case stopped(ModuleScriptStopReason)
     
     
    case quarantined(String)
     
     
    case phaseMismatch
     
    case sourceMissing(String)
     
    case sourceMismatch(expected: String, actual: String)
    case sourceTooLarge(Int)
     
     
    case busy
     
    case cancelled
}

enum ModuleScriptHostOutcome: Equatable, Sendable {
    case done(ModuleScriptResult)
     
     
     
    case aborted(message: String)
     
     
     
    case timedOut(seconds: Double)
    case skipped(ModuleScriptSkipReason)
}

enum ModuleScriptAvailability: Equatable, Sendable {
    case available
    case stopped(ModuleScriptStopReason)
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
protocol ModuleScriptHosting: AnyObject, Sendable {
    func run(
        _ script: ModuleScriptDeclaration, phase: ModuleScriptPhase?,
        request: ModuleScriptHostRequest?, response: ModuleScriptHostResponse?, body: Data?
    ) async -> ModuleScriptHostOutcome
    var availability: ModuleScriptAvailability { get }
     
    func stop(_ reason: ModuleScriptStopReason)
     
    func trim()
     
    func metrics() -> ModuleScriptHostMetrics
}

 
struct ModuleScriptHostMetrics: Codable, Equatable, Sendable {
    struct Script: Codable, Equatable, Sendable {
        var runs = 0
        var done = 0
        var aborted = 0
        var timedOut = 0
        var skipped = 0
        var sourceBytes = 0
        var lastMilliseconds = 0
         
        var footprintDeltaPeakBytes: Int64 = 0

        enum CodingKeys: String, CodingKey {
            case runs = "runs_total"
            case done = "done_total"
            case aborted = "aborted_total"
            case timedOut = "timeout_total"
            case skipped = "skipped_total"
            case sourceBytes = "source_bytes"
            case lastMilliseconds = "last_ms"
            case footprintDeltaPeakBytes = "footprint_delta_bytes_peak"
        }
    }

    var runs = 0
    var done = 0
    var aborted = 0
    var timedOut = 0
    var skipped = 0
    var contexts = 0
    var contextsPeak = 0
    var virtualMachinesCreated = 0
    var idleTrims = 0
    var sourceCacheBytes = 0
     
    var footprintBytes: Int64 = 0
    var footprintBytesPeak: Int64 = 0
     
     
    var residueBytes: Int64?
    var storeBytes = 0
     
    var quarantined = 0
    var stopped: String?
     
    var scripts: [String: Script] = [:]

    enum CodingKeys: String, CodingKey {
        case runs = "script_runs_total"
        case done = "script_done_total"
        case aborted = "script_aborted_total"
        case timedOut = "script_timeout_total"
        case skipped = "script_skipped_total"
        case contexts = "script_contexts"
        case contextsPeak = "script_contexts_peak"
        case virtualMachinesCreated = "script_vm_created_total"
        case idleTrims = "script_idle_trims_total"
        case sourceCacheBytes = "script_source_cache_bytes"
        case footprintBytes = "script_footprint_bytes"
        case footprintBytesPeak = "script_footprint_bytes_peak"
        case residueBytes = "script_residue_bytes"
        case storeBytes = "script_store_bytes"
        case quarantined = "script_quarantined"
        case stopped = "script_stopped"
        case scripts
    }
}

 
enum ModuleScriptHeaderFolding {
     
     
    static func fold(_ headers: [ModuleScriptHeader]) -> [ModuleScriptHeader] {
        var order: [String] = []
        var folded: [String: ModuleScriptHeader] = [:]
        for header in headers {
            let key = header.name.lowercased()
            if var existing = folded[key] {
                existing.value += #", "# + header.value
                folded[key] = existing
            } else {
                order.append(key)
                folded[key] = header
            }
        }
        return order.compactMap { folded[$0] }
    }

     
     
     
     
    static func unfold(_ returned: [ModuleScriptHeader], original: [ModuleScriptHeader]) -> [ModuleScriptHeader] {
        var lines: [String: [String]] = [:]
        for header in original { lines[header.name.lowercased(), default: []].append(header.value) }
        var out: [ModuleScriptHeader] = []
        for header in returned {
            if let values = lines[header.name.lowercased()], values.count > 1,
               values.joined(separator: #", "#) == header.value {
                out.append(contentsOf: values.map { ModuleScriptHeader(name: header.name, value: $0) })
            } else {
                out.append(header)
            }
        }
        return out
    }
}
#endif
