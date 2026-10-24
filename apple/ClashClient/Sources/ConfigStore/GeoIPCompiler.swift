import Foundation
import Clash

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum GeoIPCompiler {
     
     
     
     
    static func prepare(finalYAML: String) {
        prepare(finalYAML: finalYAML, geodataMode: geodataModeEnabled(in: finalYAML))
    }

     
    static func prepare(finalYAML: String, geodataMode: Bool) {
        compile(finalYAML, geodataMode: geodataMode)
    }

     
     
     
    static func geodataModeEnabled(in finalYAML: String) -> Bool {
        AppCore.geodataModeEnabled(finalYAML)
    }

     
     
     
     
    private static func compile(_ content: String, geodataMode: Bool) {
        var error: NSError?
         
         
        let summary = AppCore.prepareGeoIPCache(content, geodataMode, &error)
        guard error == nil else {
            ClashLogStore.shared.append(
                "geoip compile skipped  reason=\(error?.localizedDescription ?? "unknown")",
                stream: .app,
                level: .warning
            )
            return
        }
        ClashLogStore.shared.append(summary, stream: .app)
    }
}

extension GeoIPCompiler {
     
     
     
     
     
     
     
    static func prepareRulePayloads(in directory: URL, plan: RemoteResourcePlan, geodataMode: Bool,
                                    readPaths: [String: String] = [:]) {
         
         
        guard geodataMode else { return }
        let references = GeoSiteCompiler.referenceLines(in: directory, plan: plan, readPaths: readPaths)
        guard !references.isEmpty else { return }
        compile(references, geodataMode: geodataMode)
    }
}
