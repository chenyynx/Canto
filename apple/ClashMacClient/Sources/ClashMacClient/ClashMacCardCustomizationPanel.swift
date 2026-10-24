import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashMacCardCustomizationPanel: View {
     
    let favorites: [ClashHomeCard]
     
     
    let commit: ([ClashHomeCard]) -> Void

    @State private var cards: [ClashHomeCard]
     
    @State private var outboundModeStyle: ClashHomeOutboundModeStyle
     
     
     
     
     
     
     
     
     
    @State private var dismiss = ClashDismissHandle()

    private func close() {
        dismiss.closeModalOrDismiss()
    }

    init(
        favorites: [ClashHomeCard],
        commit: @escaping ([ClashHomeCard]) -> Void
    ) {
        self.favorites = favorites
        self.commit = commit
        _cards = State(initialValue: ClashHomeCatalog.normalized(favorites))
        _outboundModeStyle = State(
            initialValue: UserDefaults.standard
                .string(forKey: ClashHomeOutboundModeStyle.storageKey)
                .flatMap(ClashHomeOutboundModeStyle.init(rawValue:))
                ?? .spacious
        )
    }

    private var available: [ClashHomeCard] {
        ClashHomeCatalog.optionalCards.filter { !cards.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            list
            footer
        }
         
         
        .frame(width: 460, height: 580)
        .accessibilityIdentifier("home.cards.customization")
        .clashCapturesDismiss(dismiss)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clash: .copy("Customize Home"))
                .font(.headline)
            Text(clash: .copy(
                "Outbound Mode, Proxies, and Rules always stay on Home."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var list: some View {
        Form {
            Section {
                ForEach(cards, id: \.self) { card in
                    row(card) {
                         
                         
                         
                         
                         
                        rowButton(.chevronUp) { move(card, by: -1) }
                            .disabled(cards.first == card)
                            .accessibilityIdentifier(
                                "home.cards.moveUp.\(card.rawValue)"
                            )
                        rowButton(.chevronDown) { move(card, by: 1) }
                            .disabled(cards.last == card)
                            .accessibilityIdentifier(
                                "home.cards.moveDown.\(card.rawValue)"
                            )
                        if !ClashHomeCatalog.requiredCards.contains(card) {
                            rowButton(.minusCircle) {
                                cards.removeAll { $0 == card }
                            }
                            .accessibilityIdentifier(
                                "home.cards.remove.\(card.rawValue)"
                            )
                        }
                    }
                    .accessibilityIdentifier(
                        "home.cards.favorite.\(card.rawValue)"
                    )
                }
            } header: {
                Text(clash: .copy("On Home"))
            }

            if !available.isEmpty {
                Section {
                    ForEach(available, id: \.self) { card in
                        row(card) {
                            rowButton(.plusCircle) { cards.append(card) }
                                .accessibilityIdentifier(
                                    "home.cards.available.\(card.rawValue)"
                                )
                        }
                    }
                } header: {
                    Text(clash: .copy("Available"))
                }
            }

            Section {
                Picker(selection: $outboundModeStyle) {
                    ForEach(ClashHomeOutboundModeStyle.allCases, id: \.self) {
                        Text(clash: .copy($0.title)).tag($0)
                    }
                } label: {
                     
                    Text(clash: .copy("Layout"))
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .accessibilityIdentifier("home.cards.outboundModeStyle")
            }
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        .formStyle(.grouped)
    }

    private func row(
        _ card: ClashHomeCard,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            ClashSymbolImage(symbol: card.symbol)
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(clash: .copy(card.title))
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 2)
    }

     
     
     
     
    private func move(_ card: ClashHomeCard, by offset: Int) {
        guard let from = cards.firstIndex(of: card) else { return }
        let to = from + offset
        guard cards.indices.contains(to) else { return }
        cards.swapAt(from, to)
    }

    private func rowButton(
        _ symbol: ClashSymbol,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ClashSymbolImage(symbol: symbol)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }

    private var footer: some View {
        HStack {
            Button(ClashCopy.key("Reset")) {
                cards = ClashHomeCatalog.defaultCards
                outboundModeStyle = .spacious
            }
            Spacer()
            Button(ClashCopy.key("Cancel")) {
                close()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("home.cards.customization.cancel")
            Button(ClashCopy.key("Done")) {
                commit(ClashHomeCatalog.normalized(cards))
                UserDefaults.standard.set(
                    outboundModeStyle.rawValue,
                    forKey: ClashHomeOutboundModeStyle.storageKey
                )
                close()
            }
            .buttonStyle(.borderedProminent)
             
             
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }
}
