import Foundation
import SwiftUI

/// 仪表页快捷方式的持久化状态（UserDefaults key `canto.home.shortcuts.v1`）。
///
/// 规则：至少 1 个、最多 8 个；读盘时过滤未知 raw、去重并夹紧数量，脏数据不会导致空列表。
@MainActor
public final class CantoShortcutStore: ObservableObject {
    public static let storageKey = "canto.home.shortcuts.v1"
    public static let minimumCount = 1
    public static let maximumCount = 8

    @Published public private(set) var shortcuts: [CantoShortcut]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.shortcuts = Self.load(from: defaults)
    }

    /// 尚未显示的快捷方式，按 `CantoShortcut.allCases` 的顺序排列。
    public var available: [CantoShortcut] {
        let shown = Set(shortcuts)
        return CantoShortcut.allCases.filter { !shown.contains($0) }
    }

    public func isEnabled(_ shortcut: CantoShortcut) -> Bool {
        shortcuts.contains(shortcut)
    }

    public func setEnabled(_ enabled: Bool, for shortcut: CantoShortcut) {
        if enabled {
            guard shortcuts.count < Self.maximumCount, !shortcuts.contains(shortcut) else { return }
            shortcuts.append(shortcut)
        } else {
            guard shortcuts.count > Self.minimumCount,
                  let index = shortcuts.firstIndex(of: shortcut) else { return }
            shortcuts.remove(at: index)
        }
        persist()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }
        shortcuts.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    public func reset() {
        shortcuts = CantoShortcut.defaults
        persist()
    }

    private func persist() {
        defaults.set(shortcuts.map(\.rawValue), forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [CantoShortcut] {
        guard let raw = defaults.stringArray(forKey: Self.storageKey) else {
            return CantoShortcut.defaults
        }

        var seen = Set<CantoShortcut>()
        var sanitized = raw
            .compactMap(CantoShortcut.init(rawValue:))
            .filter { seen.insert($0).inserted }
        if sanitized.count > maximumCount {
            sanitized = Array(sanitized.prefix(maximumCount))
        }
        if sanitized.isEmpty {
            sanitized = CantoShortcut.defaults
        }

        // 脏数据就地修回，避免每次启动重复清洗。
        if sanitized.map(\.rawValue) != raw {
            defaults.set(sanitized.map(\.rawValue), forKey: Self.storageKey)
        }
        return sanitized
    }
}
