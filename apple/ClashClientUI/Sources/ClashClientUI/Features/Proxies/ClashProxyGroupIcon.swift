import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashProxyGroupIconKind: Equatable, Sendable {
     
    case emoji(String)
     
    case symbol(ClashSymbol)
     
     
    case remote(host: String)
     
    case unrecognized

    public static func of(_ value: String?) -> ClashProxyGroupIconKind? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return .remote(host: url.host ?? trimmed)
        }
        if trimmed.unicodeScalars.contains(where: \.properties.isEmojiPresentation) {
            return .emoji(trimmed)
        }
        if let symbol = ClashSymbol(rawValue: trimmed) {
            return .symbol(symbol)
        }
        return .unrecognized
    }
}
