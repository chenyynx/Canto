import Combine
import SwiftUI

 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashTrafficFeed: ObservableObject {
    @Published public var traffic: AppleClientTrafficSnapshot

    public init(traffic: AppleClientTrafficSnapshot) {
        self.traffic = traffic
    }
}

private struct ClashTrafficFeedKey: EnvironmentKey {
    static let defaultValue: ClashTrafficFeed? = nil
}

public extension EnvironmentValues {
     
    var clashTrafficFeed: ClashTrafficFeed? {
        get { self[ClashTrafficFeedKey.self] }
        set { self[ClashTrafficFeedKey.self] = newValue }
    }
}
