import Foundation

 
 
 
 
 
 
 
 
 
@MainActor
public enum ClashMacDebugLog {
    public static var sink: ((String) -> Void)?

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public static func note(_ line: @autoclosure () -> String) {
        let text = clock.string(from: Date()) + " " + line()
        NSLog("configuration-centre.debug:%@", text)
        sink?(text)
    }

     
     
     
    public static let fileLimitBytes = 2 * 1024 * 1024

     
    public static func fileSink(_ file: URL) -> (String) -> Void {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return { line in
            let data = Data((line + "\n").utf8)
            if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int,
               size >= fileLimitBytes {
                let aside = file.appendingPathExtension("1")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: file, to: aside)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: file, options: .atomic)
            }
        }
    }
}
