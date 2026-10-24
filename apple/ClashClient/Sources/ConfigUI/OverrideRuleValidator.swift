import Foundation
import ClashClientUI

 
 
 
 
enum OverrideRuleValidator {
     
     
    static func disallowReason(
        _ rule: String,
        runtimeProfile: ClashAppleRuntimeProfile =
            clashAppleRuntimeProfile
    ) -> String? {
        StructuredRule.disallowReason(
            rule,
            runtimeProfile: runtimeProfile
        )
    }

    static func isAllowed(
        _ rule: String,
        runtimeProfile: ClashAppleRuntimeProfile =
            clashAppleRuntimeProfile
    ) -> Bool {
        disallowReason(
            rule,
            runtimeProfile: runtimeProfile
        ) == nil
    }
}
