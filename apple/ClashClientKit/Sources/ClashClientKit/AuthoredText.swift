import Foundation

 
 
 
 
 
 
 
 
public enum AuthoredText: Hashable, Codable, Sendable {
     
    case app(String, arguments: [String] = [])
     
    case verbatim(String)

     
    public var englishText: String {
        switch self {
        case .verbatim(let text): return text
        case .app(let key, let arguments):
            var line = key
            for argument in arguments {
                guard let range = line.range(of: "%@") else { break }
                line.replaceSubrange(range, with: argument)
            }
            return line
        }
    }
}
