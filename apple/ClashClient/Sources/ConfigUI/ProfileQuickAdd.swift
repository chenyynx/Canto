import ClashClientKit
import Foundation

 
 
 
 
 
 
struct ProfileQuickAddOutcome: Equatable {
     
     
     
     
     
    struct OwnRouting: Equatable {
        let groups: Int
        let rules: Int
    }

    let id: String
    let isFirstUserProfile: Bool
    var ownRouting: OwnRouting? = nil

     
     
    static func ownRouting(of record: ConfigurationSourceRecord, suppliesOwnRouting: Bool,
                           runsAsOriginal: Bool) -> OwnRouting? {
        guard suppliesOwnRouting, !runsAsOriginal else { return nil }
        return OwnRouting(groups: record.groupCount, rules: record.ruleCount)
    }
}

enum ProfileQuickAddInput: Equatable {
     
     
    case link(String)
     
     
    case document(fileName: String, data: Data)
     
    case nodeShareLink
     
     
     
     
     
    case nodes(String)
    case nothing

    static let pastedDocumentName = "Configuration.yaml"

    static func classify(_ raw: String) -> ProfileQuickAddInput {
        switch PastedContentClassifier.classify(raw) {
        case .empty:
            return .nothing
        case .link(let url, _):
            return .link(url)
        case .configText(let body):
            return .document(fileName: pastedDocumentName, data: Data(body.utf8))
        case .nodeShareLinks:
            return .nodeShareLink
        case .unrecognized:
             
             
            return .link(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
