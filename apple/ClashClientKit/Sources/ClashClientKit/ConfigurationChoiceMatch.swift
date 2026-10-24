import Foundation

 
 
 
 
 
public enum ConfigurationChoiceMatch {
     
     
     
    public static func choice(for value: String, in choices: [String], caseInsensitive: Bool = false) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = choices.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }) {
            return exact
        }
        guard caseInsensitive else { return nil }
        let folded = trimmed.lowercased()
        return choices.first { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == folded }
    }

     
     
     
    public static func addressChoice(for value: String, in choices: [String]) -> String? {
        guard let target = address(value) else { return nil }
        return choices.first { choice in address(choice).map { $0.host == target.host && $0.port == target.port } ?? false }
    }

    private static func address(_ text: String) -> (host: String, port: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (host, port) = ConfigurationFieldValidation.splitHostPort(trimmed),
              let number = Int(port), (0...65535).contains(number) else { return nil }
        return (host.lowercased(), number)
    }
}

extension ConfigurationFieldDraft {
     
     
    public func choice(in options: [String]) -> String? {
        ConfigurationChoiceMatch.choice(for: text, in: options, caseInsensitive: readsWithoutCase)
    }
}
