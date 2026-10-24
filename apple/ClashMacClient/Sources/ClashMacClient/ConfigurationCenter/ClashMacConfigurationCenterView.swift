import ClashClientUI
import SwiftUI

 
 
 
 
 
 
public enum ClashMacConfigurationCenterSegment: Int, CaseIterable, Identifiable, Sendable {
    case configurations, nodes, rules

    public var id: Int { rawValue }

     
    public var title: String {
        switch self {
        case .configurations: "Configuration Library"
        case .nodes: "Node Library"
        case .rules: "Rule Library"
        }
    }

    public var identifier: String {
        switch self {
        case .configurations: "configurations"
        case .nodes: "nodes"
        case .rules: "rules"
        }
    }
}

 
 
 
 
 
public struct ClashMacConfigurationCenterView<Configurations: View, Nodes: View, Rules: View>: View {
    @Binding private var segment: ClashMacConfigurationCenterSegment
    private let configurations: () -> Configurations
    private let nodes: () -> Nodes
    private let rules: () -> Rules

    public init(
        segment: Binding<ClashMacConfigurationCenterSegment>,
        @ViewBuilder configurations: @escaping () -> Configurations,
        @ViewBuilder nodes: @escaping () -> Nodes,
        @ViewBuilder rules: @escaping () -> Rules
    ) {
        _segment = segment
        self.configurations = configurations
        self.nodes = nodes
        self.rules = rules
    }

    public var body: some View {
        Group {
            switch segment {
            case .configurations: configurations()
            case .nodes: nodes()
            case .rules: rules()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(selection: $segment) {
                    ForEach(ClashMacConfigurationCenterSegment.allCases) { item in
                        Text(clash: .copy(item.title)).tag(item)
                    }
                } label: {
                    Text(clash: .copy("Profile Center"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("configuration-center.segment")
            }
        }
    }
}
