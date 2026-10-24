import SwiftUI

 
 
 
 
 
 
 
 
 
public struct InheritedEntriesSection: View {
    let title: String
    let state: InheritedList
    let identifier: String
     
     
     
     
    let follow: (() -> Void)?

    public init(title: String, state: InheritedList, identifier: String, follow: (() -> Void)? = nil) {
        self.title = title
        self.state = state
        self.identifier = identifier
        self.follow = follow
    }

    public var body: some View {
        if state.override != nil {
             
             
             
             
            if let follow, state.profileDisagrees {
                Section {
                } header: {
                    HStack(spacing: ClashTheme.Spacing.compact) {
                        Text(clash: state.sourceLine)
                        ClashInlineRowActionLink(action: ClashInlineRowAction(
                            title: state.adoptProfileValueTitle,
                            identifier: "adopt-profile.\(identifier)",
                            perform: follow
                        ))
                    }
                }
            }
        } else {
            Section {
                if state.inherited.isEmpty {
                    Text(clash: .copy("No entries"))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("\(identifier).empty")
                } else {
                    ForEach(Array(state.inherited.enumerated()), id: \.offset) { index, entry in
                        Text(clash: .verbatim(entry))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("\(identifier).\(index)")
                    }
                }
            } header: {
                Text(clash: state.sourceLine)
            }
        }
    }
}

 
 
 
 
 
 
 
 
public func listState(
    override values: [String]?,
    inherited: InheritedListBase,
    upstreamDefault: PinnedDefault<[String]>
) -> InheritedList {
    InheritedList(base: inherited, override: values, upstreamDefault: upstreamDefault)
}
