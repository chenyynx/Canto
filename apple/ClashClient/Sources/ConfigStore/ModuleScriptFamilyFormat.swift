#if os(iOS) || os(macOS)
import Foundation

 
 
 

extension ModuleScriptFamily {
     
     
     
     
    init(format: ModuleFormat) {
        switch format {
        case .surge: self = .surge
        case .loon: self = .loon
        case .stash: self = .stash
        case .quantumultX: self = .quantumultX
        }
    }

     
     
     
     
     
     
     
    init(format: ModuleFormat, sourceURL: String?) {
        self.init(format: format)
        guard self == .surge, let path = sourceURL.flatMap({ URL(string: $0)?.path.lowercased() }) else { return }
        if path.hasSuffix(".module") || path.hasSuffix(".srmodule") { self = .shadowrocket }
    }
}
#endif
