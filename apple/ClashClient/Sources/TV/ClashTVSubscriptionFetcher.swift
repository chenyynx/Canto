import Foundation
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVFetchedSubscription: Equatable {
    let yaml: String
     
    let userInfo: String?
     
     
    let panelName: String?

    init(yaml: String, userInfo: String?, panelName: String? = nil) {
        self.yaml = yaml
        self.userInfo = userInfo
        self.panelName = panelName
    }
}

enum ClashTVSubscriptionFetcher {
    enum FetchError: LocalizedError, Equatable {
        case httpStatus(Int)
        case tooLarge
        case notText
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let status):
                String(localized: "The server answered \(status). Check the address on your phone.")
            case .tooLarge:
                String(localized: "The profile is larger than this Apple TV accepts.")
            case .notText:
                String(localized: "The profile did not come back as text.")
            case .transport(let reason):
                String(localized: "The profile could not be downloaded: \(reason)")
            }
        }
    }

     
     
     
     
     
     
    static let maximumBytes = Int.max

     
     
    static let maximumScriptBytes = 16 * 1024 * 1024

     
     
     
     
     
    static func userAgent(
        defaults: UserDefaults = ClientUserAgent.appGroupDefaults
    ) -> String {
        ClientUserAgent.preset(from: defaults).value
    }

    static func fetch(
        _ url: URL,
        session: URLSession,
        userAgent: String,
        maximumBytes: Int = maximumBytes
    ) async throws -> ClashTVFetchedSubscription {
        let fetched = try await fetchBody(url, session: session, userAgent: userAgent, maximumBytes: maximumBytes)
        guard let yaml = String(data: fetched.body, encoding: .utf8) else { throw FetchError.notText }
        return ClashTVFetchedSubscription(yaml: yaml, userInfo: fetched.userInfo, panelName: fetched.panelName)
    }

     
     
     
    static func fetchFile(
        _ url: URL,
        session: URLSession,
        userAgent: String,
        to target: URL
    ) async throws -> (userInfo: String?, panelName: String?) {
        let response: HTTPURLResponse?
        do {
            response = try await ClashTVBoundedDownload.file(
                for: request(url, userAgent: userAgent), session: session, maximumBytes: maximumBytes,
                to: target, allowsEmpty: true)
        } catch ClashTVBoundedDownload.Failure.tooLarge {
            throw FetchError.tooLarge
        } catch ClashTVBoundedDownload.Failure.httpStatus(let status) {
            throw FetchError.httpStatus(status)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw FetchError.transport(error.localizedDescription)
        }
        return (response?.value(forHTTPHeaderField: "subscription-userinfo"),
                PanelName.suggested(fromContentDisposition: response?.value(forHTTPHeaderField: "Content-Disposition")))
    }

     
     
    private static func request(_ url: URL, userAgent: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
         
         
         
         
         
         
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

     
     
    static func fetchBody(
        _ url: URL,
        session: URLSession,
        userAgent: String,
        maximumBytes: Int = maximumBytes
    ) async throws -> ClashTVFetchedBody {
        let request = request(url, userAgent: userAgent)
        let data: Data
        let response: HTTPURLResponse?
        do {
            (data, response) = try await ClashTVBoundedDownload.dataAndResponse(
                for: request, session: session, maximumBytes: maximumBytes
            )
        } catch ClashTVBoundedDownload.Failure.tooLarge {
            throw FetchError.tooLarge
        } catch ClashTVBoundedDownload.Failure.httpStatus(let status) {
            throw FetchError.httpStatus(status)
        } catch {
             
             
             
            if Task.isCancelled { throw CancellationError() }
            throw FetchError.transport(error.localizedDescription)
        }
        return ClashTVFetchedBody(
            body: data,
            userInfo: response?.value(forHTTPHeaderField: "subscription-userinfo"),
            panelName: PanelName.suggested(fromContentDisposition: response?.value(forHTTPHeaderField: "Content-Disposition"))
        )
    }
}

 
struct ClashTVFetchedBody: Equatable {
    let body: Data
    let userInfo: String?
    let panelName: String?
}

 
 
 
 
enum ClashTVBoundedDownload {
    enum Failure: LocalizedError, Equatable {
        case tooLarge
        case httpStatus(Int)
         
        case empty

         
         
         
        var errorDescription: String? {
            switch self {
            case .tooLarge: String(localized: "The content is larger than this Apple TV accepts.")
            case .httpStatus(let status): String(localized: "The server answered \(status).")
            case .empty: "the download was empty"
            }
        }
    }

     
     
     
     
     
     
     
     
     
    @discardableResult
    static func file(for request: URLRequest, session: URLSession, maximumBytes: Int, to target: URL,
                     allowsEmpty: Bool = false) async throws -> HTTPURLResponse? {
        let (bytes, response) = try await session.bytes(for: request)
         
        var read = false
        defer { if !read { bytes.task.cancel() } }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.httpStatus(http.statusCode)
        }
         
         
        let encoding = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding")?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if encoding.isEmpty || encoding == "identity", response.expectedContentLength > Int64(maximumBytes) {
            throw Failure.tooLarge
        }
        let directory = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).part")
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var moved = false
        defer { if !moved { try? FileManager.default.removeItem(at: partial) } }
        let handle = try FileHandle(forWritingTo: partial)
        var size = 0
        do {
            var chunk = Data()
            chunk.reserveCapacity(1 << 16)
            for try await byte in bytes {
                size += 1
                if size > maximumBytes { throw Failure.tooLarge }
                chunk.append(byte)
                if chunk.count == 1 << 16 {
                    try handle.write(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty { try handle.write(contentsOf: chunk) }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        read = true
         
         
        if size == 0, !allowsEmpty { throw Failure.empty }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
        moved = true
        return response as? HTTPURLResponse
    }

    static func data(for request: URLRequest, session: URLSession, maximumBytes: Int) async throws -> Data {
        try await dataAndResponse(for: request, session: session, maximumBytes: maximumBytes).data
    }

    static func dataAndResponse(
        for request: URLRequest,
        session: URLSession,
        maximumBytes: Int
    ) async throws -> (data: Data, response: HTTPURLResponse?) {
        let (bytes, response) = try await session.bytes(for: request)
        let http = response as? HTTPURLResponse
        if let http, !(200..<300).contains(http.statusCode) {
            throw Failure.httpStatus(http.statusCode)
        }
        if let http, http.expectedContentLength > Int64(maximumBytes) {
            throw Failure.tooLarge
        }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, Int(http?.expectedContentLength ?? 0))))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumBytes { throw Failure.tooLarge }
        }
        return (data, http)
    }
}
