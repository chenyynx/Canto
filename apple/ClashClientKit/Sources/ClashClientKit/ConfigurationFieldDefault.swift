import Foundation

 
 
 
 
 
 
 
public enum ConfigurationFieldDefaultShape: Equatable, Sendable {
     
    case none
     
    case value(String)
     
    case list([String])
     
    case map(Int)
     
    case note(String)
}

public extension ConfigurationField {
     
    var defaultShape: ConfigurationFieldDefaultShape { Self.defaultShape(of: defaultText) }

     
     
    static func defaultShape(of spelled: String?) -> ConfigurationFieldDefaultShape {
        guard let text = spelled?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text != "null", text != "~" else { return .none }
        if Self.isNote(text) { return .note(text) }
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else { return .note(text) }
            if let data = text.data(using: .utf8), let items = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return .list(items.map(Self.itemText))
            }
             
            let inner = text.dropFirst().dropLast()
            return .list(inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
        if text.hasPrefix("{") {
            guard let data = text.data(using: .utf8), let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .note(text)
            }
            return .map(map.count)
        }
        return .value(text)
    }

     
     
     
     
    var defaultNeedsWords: Bool {
        guard let text = defaultText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return false }
        return text.hasPrefix("[") || text.hasPrefix("{") || Self.isNote(text)
    }

     
     
    var defaultFlag: Bool {
        switch defaultShape {
        case .value(let text): return text == "true"
        case .note(let text): return text.split(separator: " ").first.map(String.init) == "true"
        default: return false
        }
    }

     
     
    private static func isNote(_ text: String) -> Bool {
        text.hasPrefix("=") || text.contains("(") || text.contains(" / ")
    }

    private static func itemText(_ item: Any) -> String {
        switch item {
        case let text as String: return text
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        default: return String(describing: item)
        }
    }
}
