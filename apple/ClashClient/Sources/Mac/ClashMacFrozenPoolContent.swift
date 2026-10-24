import Combine
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashMacPoolFreeze: Equatable {
    let frozen: Bool
    let epoch: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }
}

 
 
 
struct ClashMacFrozenPoolContent<Content: View>: View, Equatable {
    let freeze: ClashMacPoolFreeze
    @ViewBuilder let content: () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.freeze == rhs.freeze
    }

    var body: some View {
        content()
    }
}

 
 
struct ClashMacConnectionStateContent<Content: View>: View {
    @State private var isConnected: Bool
    private let updates: AnyPublisher<Bool, Never>
    private let content: (Bool) -> Content

    init(
        initialValue: Bool,
        updates: AnyPublisher<Bool, Never>,
        @ViewBuilder content: @escaping (Bool) -> Content
    ) {
        _isConnected = State(initialValue: initialValue)
        self.updates = updates
        self.content = content
    }

    var body: some View {
        content(isConnected)
            .onReceive(updates.removeDuplicates()) { connected in
                if isConnected != connected { isConnected = connected }
            }
    }
}
