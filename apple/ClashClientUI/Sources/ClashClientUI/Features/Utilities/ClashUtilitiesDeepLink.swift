import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashUtilitiesDeepLink {
     
     
     
     
     
    public static func presented(
        for destination: ClashUtilitiesDestination
    ) -> ClashUtilitiesDestination? {
        destination == .root ? nil : destination
    }

     
     
     
     
     
     
    public static let dismissed: ClashUtilitiesDestination = .root
}
