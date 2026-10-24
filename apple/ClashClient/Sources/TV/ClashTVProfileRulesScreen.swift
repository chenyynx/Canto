import SwiftUI

 
 
 
 
struct ClashTVProfileRulesScreen: View {
    @Binding var store: ClashTVSubscriptionStore
    let id: ClashTVSubscription.ID
     
     
     
    var onChosen: (ClashTVSubscription, Bool) -> Void = { _, _ in }

    private var chosen: ClashTVProfileRules {
        store.subscriptions.first { $0.id == id }?.effectiveRules ?? .own
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                Section("Rules") {
                    ForEach(ClashTVProfileRules.allCases) { choice in
                        Button {
                            let changed = Self.choose(choice, for: id, in: &store)
                            if let row = store.subscriptions.first(where: { $0.id == id }) { onChosen(row, changed) }
                        } label: {
                            HStack {
                                Text(choice.title)
                                Spacer()
                                if choice == chosen {
                                    Image(systemName: ClashSymbol.checkmark.rawValue)
                                }
                            }
                        }
                        .accessibilityIdentifier("tvos.subscription.rules.\(choice.rawValue)")
                    }
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)
            explanation
        }
         
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happens")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Text(ClashTVAddSubscriptionScreen.rulesExplanation)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(Self.whenItApplies)
                .font(.body)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    static var whenItApplies: String {
        String(localized: "The profile in use fetches its configuration again right away. Another profile applies the choice when it is next used.")
    }

     

     
     
    @discardableResult
    static func choose(_ choice: ClashTVProfileRules, for id: ClashTVSubscription.ID, in store: inout ClashTVSubscriptionStore) -> Bool {
        let before = store.subscriptions.first { $0.id == id }?.effectiveRules
        store.setRules(id, choice)
        return before != choice
    }
}
