import Foundation
import XCTest
import ClashClientUI

@MainActor
final class CantoShortcutStoreTests: XCTestCase {
    private func makeDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "CantoShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    func testDefaultsAreSixShortcuts() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CantoShortcutStore(defaults: defaults)

        XCTAssertEqual(
            store.shortcuts,
            [.nodes, .requests, .dnsRecords, .profiles, .modules, .lanShare]
        )
        XCTAssertEqual(store.shortcuts, CantoShortcut.defaults)
        XCTAssertEqual(store.shortcuts.count, 6)
    }

    func testSelectionSurvivesRelaunch() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CantoShortcutStore(defaults: defaults)
        store.setEnabled(false, for: .modules)
        store.setEnabled(true, for: .rules)
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        let reloaded = CantoShortcutStore(defaults: defaults)

        XCTAssertEqual(reloaded.shortcuts, store.shortcuts)
        XCTAssertEqual(
            defaults.stringArray(forKey: CantoShortcutStore.storageKey),
            store.shortcuts.map(\.rawValue)
        )
    }

    func testUnknownRawValuesAreFiltered() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            ["nodes", "not-a-shortcut", "rules"],
            forKey: CantoShortcutStore.storageKey
        )

        let store = CantoShortcutStore(defaults: defaults)

        XCTAssertEqual(store.shortcuts, [.nodes, .rules])
        XCTAssertEqual(
            defaults.stringArray(forKey: CantoShortcutStore.storageKey),
            ["nodes", "rules"]
        )
    }

    func testDuplicateRawValuesAreDeduplicated() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            ["nodes", "rules", "nodes", "rules"],
            forKey: CantoShortcutStore.storageKey
        )

        let store = CantoShortcutStore(defaults: defaults)

        XCTAssertEqual(store.shortcuts, [.nodes, .rules])
    }

    func testAtLeastOneShortcutRemains() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CantoShortcutStore(defaults: defaults)
        let removable = Array(store.shortcuts.dropFirst())
        for shortcut in removable {
            store.setEnabled(false, for: shortcut)
        }
        XCTAssertEqual(store.shortcuts, [.nodes])

        store.setEnabled(false, for: .nodes)

        XCTAssertEqual(store.shortcuts, [.nodes])
        XCTAssertTrue(store.isEnabled(.nodes))
        XCTAssertEqual(CantoShortcutStore(defaults: defaults).shortcuts, [.nodes])
    }

    func testAtMostEightShortcuts() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CantoShortcutStore(defaults: defaults)
        store.setEnabled(true, for: .rules)
        store.setEnabled(true, for: .scripts)
        XCTAssertEqual(store.shortcuts.count, 8)
        XCTAssertEqual(store.available, [.cantoAgent, .diagnostics])

        store.setEnabled(true, for: .cantoAgent)

        XCTAssertEqual(store.shortcuts.count, 8)
        XCTAssertFalse(store.isEnabled(.cantoAgent))
        XCTAssertEqual(CantoShortcutStore(defaults: defaults).shortcuts.count, 8)
    }

    func testStoredListIsClampedToEight() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            CantoShortcut.allCases.map(\.rawValue),
            forKey: CantoShortcutStore.storageKey
        )

        let store = CantoShortcutStore(defaults: defaults)

        XCTAssertEqual(store.shortcuts, Array(CantoShortcut.allCases.prefix(8)))
        XCTAssertEqual(store.shortcuts.count, 8)
    }

    func testMoveReordersAndPersists() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CantoShortcutStore(defaults: defaults)
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        XCTAssertEqual(
            store.shortcuts,
            [.requests, .nodes, .dnsRecords, .profiles, .modules, .lanShare]
        )
        XCTAssertEqual(CantoShortcutStore(defaults: defaults).shortcuts, store.shortcuts)
    }

    func testResetRestoresDefaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CantoShortcutStore(defaults: defaults)
        store.setEnabled(false, for: .nodes)
        store.setEnabled(true, for: .rules)

        store.reset()

        XCTAssertEqual(store.shortcuts, CantoShortcut.defaults)
        XCTAssertEqual(CantoShortcutStore(defaults: defaults).shortcuts, CantoShortcut.defaults)
    }

    func testCorruptStorageFallsBackToDefaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(["unknown", "unknown"], forKey: CantoShortcutStore.storageKey)
        XCTAssertEqual(CantoShortcutStore(defaults: defaults).shortcuts, CantoShortcut.defaults)

        defaults.set([String](), forKey: CantoShortcutStore.storageKey)
        XCTAssertEqual(CantoShortcutStore(defaults: defaults).shortcuts, CantoShortcut.defaults)
    }
}
