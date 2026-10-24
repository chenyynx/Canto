import Foundation
import ClashClientUI

 
 
 
 
 
 
 
 
 
 
 
enum ClashMacMenuPrimaryRow: Equatable {
     
    case intent(AppleClientConnectionIntent)
     
    case cancelStart
     
    case none

    static func resolve(
        phase: AppleClientConnectionPhase,
        intent: AppleClientConnectionIntent?
    ) -> ClashMacMenuPrimaryRow {
        if let intent { return .intent(intent) }
        switch phase {
        case .preparing: return .cancelStart
        case .disconnected, .connected, .disconnecting, .unavailable: return .none
        }
    }
}
