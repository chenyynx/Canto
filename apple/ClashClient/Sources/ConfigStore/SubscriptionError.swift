import Foundation

 
 
 
enum SubscriptionError: Error, Equatable {
    case notARemoteSource
    case badURL
    case notUTF8
}
