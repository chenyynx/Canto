import Foundation
import ClashClientUI

 
 
 
 
 
 
@MainActor
enum ClashPerfBootstrap {
    static func install() {
        ClashMainThreadHangSampler.startIfRequested()


         
         
         
        ClashPerf.sink = { line in
            ClashLogStore.shared.append(line, stream: .app, level: .info)
            FrameLogFile.append(line)
        }
         
         
         
         
         
        if ClashPageProbe.isEnabled {
            ClashPageProbe.sink = { line in
                ClashLogStore.shared.append(line, stream: .app, level: .info)
                FrameLogFile.append(line)
            }
        }
         
         
         
         
        ClashIconDiagnostics.report = { line in
            ClashLogStore.shared.append(line, stream: .app, level: .info)
             
             
             
             
             
            FrameLogFile.append(line)
        }
         
         
         
        ConfigResourceStore.lockObserver = { operation, wait, held in
             
             
             
             
            let onMain = Thread.isMainThread
            let total = wait + held
             
             
             
            guard onMain || total >= 8 else { return }
            Task { @MainActor in
                if onMain {
                    ClashPerf.span(
                        "store." + operation,
                        milliseconds: total,
                        detail: "wait=\(Int(wait))ms held=\(Int(held))ms"
                    )
                } else {
                    ClashPerf.emit(
                        String(
                            format: "bg store.%@ %.0fms wait=%dms held=%dms",
                            operation, total, Int(wait), Int(held)
                        )
                    )
                }
            }
        }
        ClashPerf.armed()
         
         
         
        ClashMainThreadHeartbeat.start()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
enum FrameLogFile {
    static let name = "clash-frames.log"
     
     
     
    private static let maximumBytes = 256 * 1024

    private static let queue = DispatchQueue(label: "network.clash.framelog")

    static var url: URL? {
        try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent(name)
    }

    static func append(_ line: String) {
        guard let url else { return }
        let stamped = Self.timestamp() + "  " + line + "\n"
        queue.async {
            guard let data = stamped.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                if let size = try? handle.offset(), size > maximumBytes {
                    try? handle.truncate(atOffset: 0)
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
