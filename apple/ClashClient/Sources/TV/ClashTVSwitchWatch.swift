import Foundation

 
 
 
 
 
 
enum ClashTVSwitchWatch {
    struct Spec: Equatable {
        let seconds: Int
        let every: Int
        let urls: [URL]

        init?(json: String) {
            guard let data = json.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let raw = root["urls"] as? [String]
            else { return nil }
            let urls = raw.compactMap(URL.init(string:))
            guard !urls.isEmpty else { return nil }
            self.urls = urls
            seconds = max(1, root["seconds"] as? Int ?? 600)
            every = max(1, root["every"] as? Int ?? 4)
        }
    }

    static func line(elapsed: Int, host: String, status: Int, milliseconds: Int, failure: String?, stage: String) -> String {
        var text = "tv switch watch: t=\(elapsed)s host=\(host) status=\(status) ms=\(milliseconds)"
        if let failure, !failure.isEmpty { text += " error=\(failure)" }
        return text + " stage=\(stage)"
    }

    @MainActor
    static func run(json: String, tunnel: ClashTVTunnelController) async {
        guard let spec = Spec(json: json) else {
            ClashLogStore.shared.append("tv switch watch: spec unreadable", stream: .app, level: .warning)
            return
        }
        let deadline = Date().addingTimeInterval(TimeInterval(spec.seconds))
        while Date() < deadline, !tunnel.state.isConnected {
            try? await Task.sleep(for: .seconds(1))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 6
        configuration.waitsForConnectivity = false
         
         
         
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        let started = Date()
        ClashLogStore.shared.append("tv switch watch: started  seconds=\(spec.seconds) every=\(spec.every) urls=\(spec.urls.map { $0.host ?? "?" }.joined(separator: ","))", stream: .app)
        while Date() < deadline {
            for url in spec.urls {
                let began = Date()
                var status = -1
                var failure: String?
                do {
                    let (_, response) = try await session.data(from: url)
                    status = (response as? HTTPURLResponse)?.statusCode ?? -1
                } catch {
                    let nsError = error as NSError
                    failure = "\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)"
                }
                let stage = tunnel.state.isConnected ? "connected" : "not-connected"
                ClashLogStore.shared.append(line(
                    elapsed: Int(Date().timeIntervalSince(started)),
                    host: url.host ?? url.absoluteString,
                    status: status,
                    milliseconds: Int(Date().timeIntervalSince(began) * 1000),
                    failure: failure,
                    stage: stage
                ), stream: .app)
            }
            try? await Task.sleep(for: .seconds(spec.every))
        }
        ClashLogStore.shared.append("tv switch watch: finished", stream: .app)
    }
}
