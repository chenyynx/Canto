#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 

 
struct ModuleScriptHTTPRequest: Equatable, Sendable {
    var method: String
    var url: String
    var headers: [ModuleScriptHeader]
    var body: Data?
     
    var timeoutSeconds: Double?
     
    var binaryMode: Bool
     
     
     
    var options: [String: String]
     
     
     
    var maximumResponseBytes: Int?

    init(method: String, url: String, headers: [ModuleScriptHeader] = [], body: Data? = nil,
         timeoutSeconds: Double? = nil, binaryMode: Bool = false, options: [String: String] = [:],
         maximumResponseBytes: Int? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeoutSeconds = timeoutSeconds
        self.binaryMode = binaryMode
        self.options = options
        self.maximumResponseBytes = maximumResponseBytes
    }
}

struct ModuleScriptHTTPResponse: Equatable, Sendable {
    var status: Int
    var headers: [ModuleScriptHeader]
    var body: Data
}

 
struct ModuleScriptNetworkFailure: Error, Equatable, Sendable {
    var message: String
}

 
 
 
struct ModuleScriptHTTPRun: Equatable, Sendable {
     
    var id: String
     
    var deadline: UInt64
}

 
 
 
 
final class ModuleScriptNetworkCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?

     
    init(_ action: (@Sendable () -> Void)? = nil) { self.action = action }

    func cancel() {
        lock.lock()
        let action = self.action
        self.action = nil
        lock.unlock()
        action?()
    }
}

 
protocol ModuleScriptNetworking: Sendable {
     
     
     
     
     
     
     
     
     
    func send(_ request: ModuleScriptHTTPRequest, run: ModuleScriptHTTPRun,
              completion: @escaping @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void)
        -> ModuleScriptNetworkCancellation
     
     
     
    func runEnded(_ id: String)
}

extension ModuleScriptNetworking {
     
    func runEnded(_ id: String) {}
}

 
 
 
struct ModuleScriptNoNetwork: ModuleScriptNetworking {
    static let unavailable = #"the network is not available to scripts here"#

    func send(_ request: ModuleScriptHTTPRequest, run: ModuleScriptHTTPRun,
              completion: @escaping @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void)
        -> ModuleScriptNetworkCancellation {
        completion(.failure(ModuleScriptNetworkFailure(message: Self.unavailable)))
        return ModuleScriptNetworkCancellation()
    }
}
#endif
