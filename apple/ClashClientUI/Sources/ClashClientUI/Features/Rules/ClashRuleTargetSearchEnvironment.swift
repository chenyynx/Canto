import ClashClientKit
import SwiftUI

 
 
 
 
 
public struct ClashRuleTargetSearchHook: @unchecked Sendable {
     
     
    public let sections: @Sendable (_ query: String, _ current: [String]) async -> [ConfigurationRuleTargetCandidates.Section]
     
    public let recordUse: @Sendable (_ name: String) -> Void

    public init(
        sections: @escaping @Sendable (_ query: String, _ current: [String]) async -> [ConfigurationRuleTargetCandidates.Section],
        recordUse: @escaping @Sendable (_ name: String) -> Void
    ) {
        self.sections = sections
        self.recordUse = recordUse
    }

     
    static let settle: UInt64 = 250_000_000
}

private struct ClashRuleTargetSearchKey: EnvironmentKey {
    static let defaultValue: ClashRuleTargetSearchHook? = nil
}

public extension EnvironmentValues {
    var clashRuleTargetSearch: ClashRuleTargetSearchHook? {
        get { self[ClashRuleTargetSearchKey.self] }
        set { self[ClashRuleTargetSearchKey.self] = newValue }
    }
}
