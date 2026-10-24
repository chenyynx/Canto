import SwiftUI

 
 
public struct ClashRulesSearchResult: Equatable, Sendable {
    public let rules: [ClashRuleLineSnapshot]
    public let total: Int

    public init(rules: [ClashRuleLineSnapshot], total: Int) {
        self.rules = rules
        self.total = max(total, rules.count)
    }
}

 
 
 
 
 
 
public struct ClashRulesSearchHook: @unchecked Sendable {
    public let search: @Sendable (_ query: String) async -> ClashRulesSearchResult?

    public init(search: @escaping @Sendable (_ query: String) async -> ClashRulesSearchResult?) {
        self.search = search
    }
}

private struct ClashRulesSearchKey: EnvironmentKey {
    static let defaultValue: ClashRulesSearchHook? = nil
}

public extension EnvironmentValues {
    var clashRulesSearch: ClashRulesSearchHook? {
        get { self[ClashRulesSearchKey.self] }
        set { self[ClashRulesSearchKey.self] = newValue }
    }
}
