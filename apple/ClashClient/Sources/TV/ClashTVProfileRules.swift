import Foundation
import ClashClientKit

 
 
 
 
 
enum ClashTVProfileRules: String, Codable, CaseIterable, Identifiable {
    case defaultRules = "default"
    case lazyRules = "lazy"
    case own = "own"

    var id: String { rawValue }

     
    static let initialChoice: ClashTVProfileRules = .defaultRules

     
    var title: String {
        switch self {
        case .defaultRules: String(localized: "Default Rules")
        case .lazyRules: String(localized: "Lazy Rules")
        case .own: String(localized: "Profile's own rules")
        }
    }

     
    var schemeID: String? {
        switch self {
        case .defaultRules: ConfigurationBuiltins.basicRuleID
        case .lazyRules: ConfigurationBuiltins.lazyRuleID
        case .own: nil
        }
    }
}
