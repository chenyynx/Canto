import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVLogsScreen: View {
    struct Snapshot: Equatable, Sendable {
        var lines: [String] = []
        var recording = true
    }

     
     
    static let limit = 400

     
     
    static let refreshInterval: Duration = .seconds(5)

     
    var reader: @Sendable () -> Snapshot = { Self.read() }

    @State private var snapshot = Snapshot()
    @State private var explained: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                ForEach(Array(snapshot.lines.enumerated()), id: \.offset) { index, line in
                     
                     
                     
                    Button {} label: {
                        Text(line)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onClashTVFocus { explained = index }
                    .accessibilityIdentifier("tvos.logs.line.\(index)")
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                Text("Logs")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Text(Self.statusValue(count: snapshot.lines.count, recording: snapshot.recording))
                    .font(.title3)
                    .accessibilityIdentifier("tvos.logs.status")
                if let explained, explained < snapshot.lines.count {
                    Text(snapshot.lines[explained])
                        .font(.body.monospaced())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(Self.explanation)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(Self.exportLine)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
             
             
            .frame(maxWidth: 520, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: explained)
        }
        .task {
             
             
             
            while !Task.isCancelled {
                let reader = reader
                let fresh = await Task.detached(priority: .utility) { reader() }.value
                if fresh != snapshot { snapshot = fresh }
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
         
    }

     
     
     
    static func reader(live: Bool) -> @Sendable () -> Snapshot {
        if live { return { Self.read() } }
        return { Self.staged }
    }

     

     
     
    static func read(
        store: ClashLogStore = .shared,
        defaults: UserDefaults? = ClashLogStore.defaultSettings(),
        limit: Int = limit
    ) -> Snapshot {
        Snapshot(
            lines: store.mergedTail(limit: limit),
            recording: defaults.map { ClashLogSettings.isRecording(from: $0) } ?? ClashLogSettings.defaultRecording
        )
    }

     
     
    static func statusValue(count: Int, recording: Bool) -> String {
        let lines: String = switch count {
        case 0: String(localized: "Nothing written yet")
        case 1: String(localized: "1 line")
        default: String(localized: "\(count) lines")
        }
        let state = recording ? String(localized: "Recording") : String(localized: "Not recording")
        return "\(lines) · \(state)"
    }

    static var explanation: String {
        String(localized: "What Clash logged, newest at the bottom.")
    }

     
    static var exportLine: String {
        String(localized: "Apple TV cannot send files, so the log is read here.")
    }

     
     
    static let staged = Snapshot(
        lines: [
            "2026-09-29T02:14:05.120Z  INFO  tv connect requested",
            "2026-09-29T02:14:05.388Z  INFO  time=\"2026-09-29T02:14:05Z\" level=info msg=\"Start initial configuration in progress\"",
            "2026-09-29T02:14:05.402Z  INFO  time=\"2026-09-29T02:14:05Z\" level=info msg=\"Geodata Loader mode: standard\"",
            "2026-09-29T02:14:06.017Z  INFO  time=\"2026-09-29T02:14:06Z\" level=info msg=\"Initial configuration complete, total time: 629ms\"",
            "2026-09-29T02:14:06.020Z  INFO  time=\"2026-09-29T02:14:06Z\" level=info msg=\"Mixed(http+socks) proxy listening at: 127.0.0.1:7890\"",
            "2026-09-29T02:14:06.211Z  INFO  tv tunnel established",
            "2026-09-29T02:14:31.904Z  WARNING  time=\"2026-09-29T02:14:31Z\" level=warning msg=\"[TCP] dial Proxy (match GeoSite/geolocation-!cn) 192.168.1.20:52144 --> www.example.com:443 error: dial tcp 203.0.113.10:443: i/o timeout\"",
            "2026-09-29T02:14:32.118Z  INFO  time=\"2026-09-29T02:14:32Z\" level=info msg=\"[TCP] 192.168.1.20:52150 --> www.example.com:443 match GeoSite(geolocation-!cn) using Proxy[Node 2]\"",
        ],
        recording: true
    )
}
