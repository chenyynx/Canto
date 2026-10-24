import ClashClientKit
import SwiftUI

 
 
 
 
 
 
public struct ClashMacEditorSyntax: Sendable {
    public struct RuleType: Equatable, Sendable {
        public let name: String
         
        public let payload: String
         
         
        public let options: [String]
         
        public let logical: Bool
         
         
        public let matchesHere: Bool
        public init(name: String, payload: String, options: [String], logical: Bool, matchesHere: Bool = true) {
            self.name = name; self.payload = payload; self.options = options; self.logical = logical
            self.matchesHere = matchesHere
        }
    }
    public var ruleTypes: [RuleType]
    public var groupTypes: [String]
    public var fields: ConfigurationFieldCatalog?

    public init(ruleTypes: [RuleType], groupTypes: [String], fields: ConfigurationFieldCatalog?) {
        self.ruleTypes = ruleTypes; self.groupTypes = groupTypes; self.fields = fields
    }
}

private struct ClashMacEditorSyntaxKey: EnvironmentKey {
    static let defaultValue: ClashMacEditorSyntax? = nil
}

public extension EnvironmentValues {
     
     
    var clashMacEditorSyntax: ClashMacEditorSyntax? {
        get { self[ClashMacEditorSyntaxKey.self] }
        set { self[ClashMacEditorSyntaxKey.self] = newValue }
    }
}
