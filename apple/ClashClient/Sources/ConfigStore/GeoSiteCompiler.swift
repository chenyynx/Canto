import Foundation
import Clash

 
 
 
 
 
 
 
 
 
 
 
 
 
enum GeoSiteCompiler {
     
     
     
    static func prepare(finalYAML: String) {
        var error: NSError?
         
         
         
        let summary = AppCore.prepareGeoSiteCache(finalYAML, &error)
        guard error == nil else {
            ClashLogStore.shared.append(
                "geosite compile skipped  reason=\(error?.localizedDescription ?? "unknown")",
                stream: .app,
                level: .warning
            )
            return
        }
        ClashLogStore.shared.append(summary, stream: .app)
    }
}

extension GeoSiteCompiler {
     
     
     
    static func prepareRulePayloads(in directory: URL, plan: RemoteResourcePlan, readPaths: [String: String] = [:]) {
        let references = referenceLines(in: directory, plan: plan, readPaths: readPaths)
        guard !references.isEmpty else { return }
        prepare(finalYAML: references)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func referenceLines(in directory: URL, plan: RemoteResourcePlan, readPaths: [String: String] = [:],
                               chunkBytes: Int = 1 << 20) -> String {
        var kept: [String] = []
        for provider in plan.providers where provider.kind == "rule" && provider.format.lowercased() != "mrs"
            && !["domain", "ipcidr"].contains(provider.behavior.trimmingCharacters(in: .whitespaces).lowercased()) {
            let file = readPaths[provider.name].map { URL(fileURLWithPath: $0) }
                ?? directory.appendingPathComponent(provider.path)
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
             
             
            var piece = Data()
            func finish() {
                if namesGeo(piece) { kept.append(String(decoding: piece, as: UTF8.self)) }
                piece.removeAll(keepingCapacity: true)
            }
            while let chunk = try? handle.read(upToCount: chunkBytes), !chunk.isEmpty {
                chunk.withUnsafeBytes { bytes in
                    var start = 0
                    for index in 0..<bytes.count where endsReference(bytes[index]) {
                        piece.append(contentsOf: bytes[start..<index])
                        finish()
                        start = index + 1
                    }
                    piece.append(contentsOf: bytes[start..<bytes.count])
                }
            }
            finish()
        }
        return kept.joined(separator: "\n")
    }

     
    private static func endsReference(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x0A, 0x0D, 0x22, 0x27, 0x5D, 0x23, 0x28, 0x29: true    
        default: false
        }
    }

    private static func namesGeo(_ piece: Data) -> Bool {
        piece.withUnsafeBytes { bytes in
            guard bytes.count >= 3 else { return false }
            for index in 0..<(bytes.count - 2) where bytes[index] | 0x20 == 0x67
                && bytes[index + 1] | 0x20 == 0x65 && bytes[index + 2] | 0x20 == 0x6F {
                return true
            }
            return false
        }
    }
}
