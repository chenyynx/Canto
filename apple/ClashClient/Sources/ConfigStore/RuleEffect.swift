import Foundation
import Clash

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum RuleEffect {
     
     
     
     
     
     
     
    case neverMatches
    case matchesEverything
     
     
    case unjudged

    static func of(_ rule: String) -> RuleEffect {
        switch ClashRuleEffectForIOS(rule) {
        case ClashRuleEffectNeverMatches: .neverMatches
        case ClashRuleEffectMatchesEverything: .matchesEverything
        default: .unjudged
        }
    }

     
     
     
    static func neverMatches(_ rule: String) -> Bool {
        of(rule) == .neverMatches
    }
}
