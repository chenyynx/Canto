import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum GlobalModeConfirmation {

    enum Verdict: Equatable {
         
        case confirmed
         
         
        case refused
         
         
         
        case notYetKnown
    }

     
     
     
     
     
     
     
     
     
     
     
    static func verdict(
        groupCount: Int,
        hasGlobalGroup: Bool = true,
        selectionConfirmed: Bool
    ) -> Verdict {
        guard groupCount > 0, hasGlobalGroup else { return .notYetKnown }
        return selectionConfirmed ? .confirmed : .refused
    }
}
