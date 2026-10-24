import Foundation
import Clash

 
 
 
 
 
 
 
 
 
 
 
enum SideUpdateDeferral {
    static func isDeferred(_ error: Error) -> Bool {
        (error as NSError).localizedDescription
            .hasPrefix(ClashSideUpdateDeferredPrefix)
    }

     
     
    static func displayMessage(_ error: Error) -> String {
        let text = (error as NSError).localizedDescription
        guard text.hasPrefix(ClashSideUpdateDeferredPrefix) else { return text }
        return String(text.dropFirst(ClashSideUpdateDeferredPrefix.count))
    }
}
