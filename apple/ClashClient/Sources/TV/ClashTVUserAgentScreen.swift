import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVUserAgentScreen: View {
    @State private var selected: ClientUserAgent.Preset
    @State private var focused: ClientUserAgent.Preset?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = ClientUserAgent.appGroupDefaults) {
        self.defaults = defaults
        _selected = State(initialValue: ClientUserAgent.preset(from: defaults))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                Section("User-Agent") {
                    ForEach(ClientUserAgent.Preset.allCases) { preset in
                        Button {
                            ClientUserAgent.save(preset: preset, in: defaults)
                            selected = preset
                        } label: {
                            HStack {
                                Text(preset.label.localizedForTelevision)
                                Spacer()
                                if preset == selected {
                                    Image(systemName: ClashSymbol.checkmark.rawValue)
                                }
                            }
                        }
                        .onClashTVFocus { focused = preset }
                        .accessibilityIdentifier("tvos.userAgent.\(preset.rawValue)")
                    }
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 20) {
                let shown = focused ?? selected
                Text(shown.label.localizedForTelevision)
                    .font(.title2)
                Text(shown.value)
                    .font(.body)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tvos.userAgent.value")
                if shown == .clash {
                    Text("Clash, followed by this Apple TV. Keep this unless your profile URL works better with another.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)
        }
        .navigationTitle("User-Agent")
    }
}
