import SwiftUI

/// 快捷方式编辑页：已显示项可拖动排序、取消勾选；可添加项点击加入。
///
/// 自包含原生 List，不依赖 CantoTheme 或产品级容器，方便仪表页先接线。
public struct CantoShortcutEditorView: View {
    @ObservedObject private var store: CantoShortcutStore
    @Environment(\.locale) private var locale
    private let onDone: () -> Void

    public init(store: CantoShortcutStore, onDone: @escaping () -> Void = {}) {
        self.store = store
        self.onDone = onDone
    }

    public var body: some View {
        #if os(macOS)
        // macOS sheet 上工具栏不一定可达，这里用自包含头部保证「完成 / 恢复默认」可点。
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    store.reset()
                } label: {
                    Text("Reset")
                }
                .accessibilityLabel(Text("Reset to Defaults"))
                .accessibilityIdentifier("shortcuts.editor.reset")

                Spacer(minLength: 0)

                Button(action: onDone) {
                    Text("Done")
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("shortcuts.editor.done")
            }
            .padding()
            Divider()
            list
        }
        .frame(minWidth: 420, minHeight: 480)
        #else
        NavigationView {
            list
                .navigationTitle(Text("Edit Shortcuts"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            store.reset()
                        } label: {
                            Text("Reset")
                        }
                        .accessibilityLabel(Text("Reset to Defaults"))
                        .accessibilityIdentifier("shortcuts.editor.reset")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onDone) {
                            Text("Done")
                        }
                        .accessibilityIdentifier("shortcuts.editor.done")
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        #endif
    }

    private var list: some View {
        List {
            shownSection
            availableSection
        }
        #if os(iOS)
        // 常驻编辑态：iOS 上 onMove 的拖动手柄只在 EditMode 激活时出现。
        .environment(\.editMode, .constant(.active))
        #endif
    }

    private var shownSection: some View {
        Section {
            ForEach(store.shortcuts) { shortcut in
                shownRow(shortcut)
                    .accessibilityIdentifier("shortcuts.editor.shown.\(shortcut.rawValue)")
            }
            .onMove { source, destination in
                store.move(fromOffsets: source, toOffset: destination)
            }
        } header: {
            Text("Shown")
        } footer: {
            if isAtMinimum {
                Text("At least one shortcut must stay shown.")
            } else {
                Text("Drag to reorder. Tap a shortcut to hide it.")
            }
        }
    }

    private var availableSection: some View {
        Section {
            ForEach(store.available) { shortcut in
                availableRow(shortcut)
                    .accessibilityIdentifier("shortcuts.editor.available.\(shortcut.rawValue)")
            }
        } header: {
            Text("Available")
        } footer: {
            if store.available.isEmpty {
                Text("All shortcuts are shown. Hide one to make room.")
            } else {
                Text("Tap a shortcut to show it. Up to \(CantoShortcutStore.maximumCount) shortcuts can be shown.")
            }
        }
    }

    private var isAtMinimum: Bool {
        store.shortcuts.count <= CantoShortcutStore.minimumCount
    }

    private func shownRow(_ shortcut: CantoShortcut) -> some View {
        shortcutRow(shortcut, selected: true, locked: isAtMinimum) {
            store.setEnabled(false, for: shortcut)
        }
        .accessibilityHint(
            isAtMinimum
                ? Text("At least one shortcut must stay shown.")
                : Text("Hides this shortcut on the dashboard.")
        )
    }

    private func availableRow(_ shortcut: CantoShortcut) -> some View {
        shortcutRow(shortcut, selected: false, locked: false) {
            store.setEnabled(true, for: shortcut)
        }
        .accessibilityHint(Text("Shows this shortcut on the dashboard."))
    }

    private func shortcutRow(
        _ shortcut: CantoShortcut,
        selected: Bool,
        locked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        // editMode 常驻时 List 行内 Button 不触发动作（SwiftUI 已知行为），
        // 所以用行级 tap 手势 + 无障碍按钮语义，保证编辑态仍能勾选/取消。
        HStack(spacing: 12) {
            Image(systemName: shortcut.systemImage)
                .font(.body)
                .foregroundStyle(shortcut.tint)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ClashCopy.string(shortcut.titleKey, locale: locale))
                    .foregroundStyle(.primary)
                if let subtitleKey = shortcut.subtitleKey {
                    Text(verbatim: ClashCopy.string(subtitleKey, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(!locked)
        .onTapGesture {
            guard !locked else { return }
            action()
        }
        .opacity(locked ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ClashCopy.string(shortcut.titleKey, locale: locale)))
        .accessibilityValue(Text(verbatim: ClashCopy.string(selected ? "Shown" : "Not shown", locale: locale)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !locked else { return }
            action()
        }
    }
}
