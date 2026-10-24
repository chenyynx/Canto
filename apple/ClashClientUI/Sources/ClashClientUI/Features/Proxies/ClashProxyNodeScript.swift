import Foundation

 
 
 
 
 
public struct ClashProxyNodeScript: Codable, Equatable, Hashable, Identifiable, Sendable {
     
    public var id: String
     
    public var name: String
     
     
    public var symbol: String?

    public init(id: String, name: String, symbol: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}
