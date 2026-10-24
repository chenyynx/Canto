import SwiftUI

 
struct ClashTVAutoUpdateScreen: View {
    @Binding var store: ClashTVSubscriptionStore
    let id: ClashTVSubscription.ID
    var onChosen: (ClashTVSubscription) -> Void = { _ in }

     
    static let choices = [0, 1, 6, 12, 24, 48, 168]

    static func title(forHours hours: Int) -> String {
        hours <= 0 ? String(localized: "Manually") : String(localized: "Every \(hours) hours")
    }

    static func identifier(forHours hours: Int) -> String {
        hours <= 0 ? "manual" : "\(hours)h"
    }

    private var chosen: Int {
        store.subscriptions.first { $0.id == id }?.updateIntervalHours ?? 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                Section("Auto update") {
                    ForEach(Self.choices, id: \.self) { hours in
                        Button {
                            store.setUpdateInterval(id, hours: hours)
                            if let row = store.subscriptions.first(where: { $0.id == id }) { onChosen(row) }
                        } label: {
                            HStack {
                                Text(Self.title(forHours: hours))
                                Spacer()
                                if hours == chosen {
                                    Image(systemName: ClashSymbol.checkmark.rawValue)
                                }
                            }
                        }
                        .accessibilityIdentifier("tvos.subscription.auto-update.\(Self.identifier(forHours: hours))")
                    }
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                Text("What happens")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Text("The profile in use is fetched again once this long has passed since it last updated — when Clash opens, and in the background when tvOS allows it. The interval is the earliest a fetch may happen, not a promised time.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
