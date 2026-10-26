import SwiftUI
import ClashClientUI

/// 把 `NodesModel` 的策略组数据接到 Canto 的新策略页；
/// 组选择仍走现有 `NodesModel.select`，不复制节点/测速逻辑。
struct CantoPolicyHost: View {
    @ObservedObject var nodes: NodesModel
    @State private var selectedGroupName: String?

    var body: some View {
        CantoPolicyView(
            title: "Policy",
            items: items,
            onSelect: { selectedGroupName = $0 }
        )
        .sheet(
            isPresented: Binding(
                get: { selectedGroupName != nil },
                set: { if !$0 { selectedGroupName = nil } }
            )
        ) {
            if let group = selectedGroup {
                CantoPolicyNodePicker(nodes: nodes, group: group)
            }
        }
    }

    private var selectedGroup: ProxyGroup? {
        guard let selectedGroupName else { return nil }
        return nodes.groups.first { $0.name == selectedGroupName }
    }

    private var items: [CantoPolicyItem] {
        nodes.groups
            .filter { !$0.hidden }
            .enumerated()
            .map { index, group in
                let now = group.resolvedNow.isEmpty ? group.now : group.resolvedNow
                return CantoPolicyItem(
                    id: group.name,
                    title: group.name,
                    subtitle: now.isEmpty ? "DIRECT" : now,
                    systemImage: symbol(for: group.type),
                    tint: tint(for: index),
                    isSelected: group.fixed != nil,
                    latency: nodes.delays[group.now].map { "\($0) ms" }
                )
            }
    }

    private func symbol(for type: String) -> String {
        switch type.lowercased() {
        case "select", "selector":
            return "square.stack.3d.up.fill"
        case "url-test", "urltest":
            return "bolt.horizontal.fill"
        case "fallback":
            return "arrow.triangle.2.circlepath"
        case "load-balance", "loadbalance":
            return "scale.3d"
        default:
            return "square.stack.3d.up.fill"
        }
    }

    private func tint(for index: Int) -> Color {
        switch index % 4 {
        case 0: CantoTheme.Palette.accent
        case 1: CantoTheme.Palette.success
        case 2: CantoTheme.Palette.warning
        default: CantoTheme.Palette.secondaryInk
        }
    }
}

private struct CantoPolicyNodePicker: View {
    @ObservedObject var nodes: NodesModel
    let group: ProxyGroup

    @Environment(\.dismiss) private var dismiss
    @State private var selecting: String?

    var body: some View {
        NavigationView {
            List {
                ForEach(group.members, id: \.self) { member in
                    Button {
                        select(member)
                    } label: {
                        HStack(spacing: CantoTheme.Spacing.row) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: group.memberResolvedNames[member] ?? member)
                                    .font(CantoTheme.Typography.rowTitle)
                                    .foregroundStyle(CantoTheme.Palette.ink)
                                if let delay = nodes.delays[member] {
                                    Text(verbatim: "\(delay) ms")
                                        .font(CantoTheme.Typography.caption.monospacedDigit())
                                        .foregroundStyle(CantoTheme.Palette.secondaryInk)
                                }
                            }
                            Spacer(minLength: CantoTheme.Spacing.compact)
                            if group.now == member {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(CantoTheme.Palette.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selecting != nil)
                }
            }
            .navigationTitle(Text(verbatim: group.name))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text(clash: .copy("Cancel"))
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func select(_ member: String) {
        guard selecting == nil else { return }
        selecting = member
        Task {
            await nodes.select(group: group.name, name: member)
            selecting = nil
            dismiss()
        }
    }
}
