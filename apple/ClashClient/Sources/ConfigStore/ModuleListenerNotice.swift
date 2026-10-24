import ClashClientKit
import Foundation

 
 
 
 
 
 
 
 
enum ModuleListenerNotice {
     
     
     
    private static let needle = ["listeners", "declares"].joined(separator: " ")

     
     
     
     
     
     
    static func note(for notice: String, record: ModuleActivationRecord?) -> AuthoredText? {
        guard let record, let range = notice.range(of: needle) else { return nil }
        let digits = notice[range.upperBound...].drop(while: { $0 == " " }).prefix(while: { $0.isASCII && $0.isNumber })
        guard let count = Int(digits), count == record.userListenerCount + 1 else { return nil }
         
         
        return .app("This port is for this device only.")
    }
}
