import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVDNSScreen: View {
    enum Section: Hashable, CaseIterable {
        case enhancedMode, nameserver, fallback, defaultNameserver

        var kernelKey: String {
            switch self {
            case .enhancedMode: "enhanced-mode"
            case .nameserver: "nameserver"
            case .fallback: "fallback"
            case .defaultNameserver: "default-nameserver"
            }
        }

        var explanation: String {
            switch self {
            case .enhancedMode:
                String(localized: "How Clash looks up a name. fake-ip answers at once with a stand-in address; redir-host looks up the real address first.")
            case .nameserver:
                String(localized: "The DNS servers asked first, in this order.")
            case .fallback:
                String(localized: "Asked when the first answer can't be trusted.")
            case .defaultNameserver:
                String(localized: "Used to find the DNS servers above when they are given by name.")
            }
        }
    }

    static var explanation: String {
        String(localized: "The DNS servers Clash uses, from the profile. They can't be changed on Apple TV.")
    }

    @Binding var state: ClashTVProductState

    @State private var explained: Section = .enhancedMode

     
     
     
     
     
     
     
     
    static func rows(for values: [String]) -> [String] {
        let kept = values.filter { !$0.isEmpty }
        return kept.isEmpty ? ["—"] : kept
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                SwiftUI.Section {
                    ForEach(Self.rows(for: [state.dnsEnhancedMode]), id: \.self) { row($0, in: .enhancedMode) }
                } header: { header(.enhancedMode) }
                SwiftUI.Section {
                    ForEach(Self.rows(for: state.dnsNameservers), id: \.self) { row($0, in: .nameserver) }
                } header: { header(.nameserver) }
                SwiftUI.Section {
                    ForEach(Self.rows(for: state.dnsFallback), id: \.self) { row($0, in: .fallback) }
                } header: { header(.fallback) }
                SwiftUI.Section {
                    ForEach(Self.rows(for: state.dnsDefaultNameservers), id: \.self) { row($0, in: .defaultNameserver) }
                } header: { header(.defaultNameserver) }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                Text(explained.kernelKey)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                Text(explained.explanation)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(Self.explanation)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: explained)
        }
    }

     
     
     
    private func header(_ section: Section) -> some View {
        Text(section.kernelKey)
            .font(.caption.monospaced())
            .textCase(nil)
    }

    private func row(_ value: String, in section: Section) -> some View {
        Button {} label: {
            Text(value)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onClashTVFocus { explained = section }
    }
}
