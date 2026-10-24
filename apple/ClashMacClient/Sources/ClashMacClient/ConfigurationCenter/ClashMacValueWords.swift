import Foundation
import ClashClientKit
import ClashClientUI

 
 
 
 
enum ClashMacValueWords {
     
    static let device = "Mac"

     
     
     
     
     
     
     
    static func defaultLine(_ field: ConfigurationField?, locale: Locale,
                            copy: ConfigurationFieldCopy = .shared) -> ClashDisplayText {
        guard let field else { return .copy("Not set") }
        if let unset = copy.entry(for: field, locale: locale)?.unset, !unset.isEmpty {
             
             
            return .format("Default: %@", [copy.valueLabel(unset, for: field, locale: locale) ?? unset])
        }
        if case .value(let text) = field.defaultShape, let label = copy.valueLabel(text, for: field, locale: locale) {
            return .format("Default: %@", [label])
        }
        return ConfigurationValueWords.defaultWords(for: field, locale: locale) ?? .copy("Not set")
    }

     
     
     
     
    static func valueName(_ value: String, path: String, copy: ConfigurationFieldCopy = .shared, locale: Locale) -> String {
        valueNames(path: path, copy: copy, locale: locale)[value.lowercased()] ?? value
    }

     
     
     
    static func valueNames(path: String, copy: ConfigurationFieldCopy = .shared, locale: Locale) -> [String: String] {
        let presets = copy.entry(forPath: path, language: ConfigurationFieldCopy.Language(locale: locale))?.presets ?? []
        return Dictionary(presets.map { ($0.value.lowercased(), $0.label) }, uniquingKeysWith: { first, _ in first })
    }

     
     
     
     
    static func placeholder(_ field: ConfigurationField?, locale: Locale,
                            copy: ConfigurationFieldCopy = .shared) -> String? {
        ConfigurationValueWords.defaultPrompt(for: field, locale: locale, copy: copy)
    }
}
