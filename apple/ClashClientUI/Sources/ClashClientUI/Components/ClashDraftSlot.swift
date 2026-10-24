import Foundation

 
public struct ClashRestoredDraft: Equatable, Sendable {
    public let text: String
     
     
    public let needsNotice: Bool
     
     
    public let originalChanged: Bool
    public init(text: String, needsNotice: Bool, originalChanged: Bool = false) {
        self.text = text
        self.needsNotice = needsNotice
        self.originalChanged = originalChanged
    }
}

 
 
 
 
 
 
 
public protocol ClashUnsavedDraftStore: AnyObject, Sendable {
     
     
    func restoreDraft(key: String, original: String) -> ClashRestoredDraft?
     
     
    func recordDraft(key: String, original: String, text: String)
    func clearDraft(key: String)
}

 
 
 
 
public struct ClashDraftSlot<Value: Codable & Equatable> {
    public let key: String
     
    public let original: Value
     
     
     
     
    private let basis: Value
    private let basisText: String
     
    private let sameBasis: (_ recorded: Value, _ current: Value) -> Bool
    private let store: (any ClashUnsavedDraftStore)?
    private let committed = CommitMark()

    private final class CommitMark {
        var isSet = false
    }

     
     
     
     
     
     
     
    public init(key: String, original: Value, store: (any ClashUnsavedDraftStore)?, basis: Value? = nil,
                sameBasis: ((_ recorded: Value, _ current: Value) -> Bool)? = nil) {
        self.key = key
        self.original = original
        self.store = store
        self.basis = basis ?? original
        basisText = Self.text(basis ?? original)
        self.sameBasis = sameBasis ?? { $0 == $1 }
    }

     
    private struct Recorded: Codable {
        var basis: Value
        var value: Value
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func opening() -> (value: Value, needsNotice: Bool) {
        guard let restored = store?.restoreDraft(key: key, original: basisText) else { return (original, false) }
        let value: Value
        if let recorded = try? JSONDecoder().decode(Recorded.self, from: Data(restored.text.utf8)) {
            guard sameBasis(recorded.basis, basis) else { return dropped() }
            value = recorded.value
        } else if let legacy = Self.value(from: restored.text), !restored.originalChanged {
            value = legacy
        } else {
            return dropped()
        }
        guard value != original else { return (original, false) }
        return (value, true)
    }

    private func dropped() -> (value: Value, needsNotice: Bool) {
        store?.clearDraft(key: key)
        return (original, false)
    }

     
    public func record(_ value: Value) {
        guard !committed.isSet else { return }
        guard value != original else { return clear() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Recorded(basis: basis, value: value)) else { return }
        store?.recordDraft(key: key, original: basisText, text: String(decoding: data, as: UTF8.self))
    }

     
     
     
    public func commit() {
        committed.isSet = true
        clear()
    }

    public func clear() {
        store?.clearDraft(key: key)
    }

    static func text(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static func value(from text: String) -> Value? {
        try? JSONDecoder().decode(Value.self, from: Data(text.utf8))
    }
}
