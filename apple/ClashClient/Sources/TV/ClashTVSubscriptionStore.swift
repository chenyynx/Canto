import Foundation
import ClashClientKit

 
 
 
 
 
 
 
 
 
struct ClashTVSubscription: Codable, Equatable, Identifiable {
     
     
     
    let requestURL: URL
    let name: String
     
     
     
    let updatedAt: Date?
     
     
     
    let restored: Restored?
     
     
     
     
    let rules: ClashTVProfileRules?
     
     
     
     
     
     
    let scriptURL: URL?
     
     
     
     
     
    let updateIntervalHours: Int?

    init(requestURL: URL, name: String, updatedAt: Date? = nil, restored: Restored? = nil,
         rules: ClashTVProfileRules? = nil, scriptURL: URL? = nil, updateIntervalHours: Int? = nil) {
        self.requestURL = requestURL
        self.name = name
        self.updatedAt = updatedAt
        self.restored = restored
        self.rules = rules
        self.scriptURL = scriptURL
        self.updateIntervalHours = updateIntervalHours
    }

     
    func withScriptURL(_ scriptURL: URL?) -> ClashTVSubscription {
        ClashTVSubscription(requestURL: requestURL, name: name, updatedAt: updatedAt, restored: restored, rules: rules, scriptURL: scriptURL, updateIntervalHours: updateIntervalHours)
    }

     
    func withUpdateInterval(hours: Int?) -> ClashTVSubscription {
        ClashTVSubscription(requestURL: requestURL, name: name, updatedAt: updatedAt, restored: restored, rules: rules, scriptURL: scriptURL, updateIntervalHours: hours)
    }

    var effectiveRules: ClashTVProfileRules { rules ?? .own }

     
     
    func withRules(_ rules: ClashTVProfileRules) -> ClashTVSubscription {
        ClashTVSubscription(requestURL: requestURL, name: name, updatedAt: updatedAt, restored: restored, rules: rules, scriptURL: scriptURL, updateIntervalHours: updateIntervalHours)
    }

    struct Restored: Codable, Equatable {
        let archiveProfileID: String
        let sourceInstallID: String
        let sourceDevice: String
        let exportedAt: Date
         
         
        let overridesApplied: Bool
         
        let sourceKind: String
         
         
        var followsAutoBackup: Bool { overridesApplied }
    }

     
     
     
    static let restoredScheme = "clash-restore"

    static func placeholderURL(archiveProfileID: String) -> URL {
        URL(string: "\(restoredScheme)://\(archiveProfileID)")!
    }

     
    var hasFetchableAddress: Bool { requestURL.scheme != Self.restoredScheme }

     
     
    var id: URL { requestURL }

     
     
    var displayURL: URL { requestURL }

     
     
    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !hasFetchableAddress { return String(localized: "Restored profile") }
        return displayURL.host ?? displayURL.absoluteString
    }
}

 
 
enum ClashTVSubscriptionEditError: Error, Equatable, LocalizedError {
     
    case addressAlreadyRemembered(String)

     
     
     
    var errorDescription: String? {
        switch self {
        case .addressAlreadyRemembered(let name):
            String(localized: "This address is already in the list, as “\(name)”.")
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVSubscriptionStore: @unchecked Sendable {
    static let key = "clash.tv.subscriptions"
    static let currentKey = "clash.tv.subscriptions.current"

    private let defaults: UserDefaults
    private(set) var subscriptions: [ClashTVSubscription]
     
     
    private var chosenID: ClashTVSubscription.ID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([ClashTVSubscription].self, from: data) {
             
             
             
             
            var seen = Set<ClashTVSubscription.ID>()
            subscriptions = decoded.filter { seen.insert($0.id).inserted }
        } else {
            subscriptions = []
        }
        chosenID = defaults.string(forKey: Self.currentKey).flatMap(URL.init(string:))
    }

     
     
    var current: ClashTVSubscription? {
        subscriptions.first { $0.id == chosenID } ?? subscriptions.last
    }

     
     
     
     
     
     
     
     
     
     
    @discardableResult
    mutating func add(urlString: String, name: String, rules: ClashTVProfileRules = .own) throws -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw ProfileValidationError.invalidRemoteURL
        }
        _ = try Profile.RemoteSource(requestURL: url)
        let existed = subscriptions.contains { $0.id == url }
        if let index = subscriptions.firstIndex(where: { $0.id == url }) {
            let existing = subscriptions[index]
            let typedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            subscriptions[index] = ClashTVSubscription(
                requestURL: url, name: typedName.isEmpty ? existing.name : name,
                updatedAt: existing.updatedAt, restored: existing.restored, rules: rules,
                scriptURL: existing.scriptURL, updateIntervalHours: existing.updateIntervalHours
            )
        } else {
            subscriptions.append(ClashTVSubscription(requestURL: url, name: name, rules: rules, updateIntervalHours: Self.defaultUpdateIntervalHours))
        }
        chosenID = url
        persist()
        return existed
    }

     
     
    mutating func use(_ id: ClashTVSubscription.ID) {
        guard subscriptions.contains(where: { $0.id == id }) else { return }
        chosenID = id
        persist()
    }

     
     
     
    mutating func rename(_ id: ClashTVSubscription.ID, to name: String) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        let existing = subscriptions[index]
        subscriptions[index] = ClashTVSubscription(
            requestURL: existing.requestURL,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: existing.updatedAt,
            restored: existing.restored,
            rules: existing.rules,
            scriptURL: existing.scriptURL, updateIntervalHours: existing.updateIntervalHours
        )
        persist()
    }

     
     
     
    mutating func setRules(_ id: ClashTVSubscription.ID, _ rules: ClashTVProfileRules) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        let existing = subscriptions[index]
        subscriptions[index] = ClashTVSubscription(
            requestURL: existing.requestURL, name: existing.name, updatedAt: existing.updatedAt,
            restored: existing.restored, rules: rules, scriptURL: existing.scriptURL, updateIntervalHours: existing.updateIntervalHours
        )
        persist()
    }

     
    static let defaultUpdateIntervalHours = 12

    mutating func setUpdateInterval(_ id: ClashTVSubscription.ID, hours: Int?) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index] = subscriptions[index].withUpdateInterval(hours: hours)
        persist()
    }

    mutating func setScriptURL(_ id: ClashTVSubscription.ID, _ scriptURL: URL?) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index] = subscriptions[index].withScriptURL(scriptURL)
        persist()
    }

     
     
     
    static func scriptURL(from text: String) throws -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host?.isEmpty == false
        else { throw ProfileValidationError.invalidRemoteURL }
        return url
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    mutating func edit(_ id: ClashTVSubscription.ID, name: String, urlString: String) throws -> Bool {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw ProfileValidationError.invalidRemoteURL
        }
        _ = try Profile.RemoteSource(requestURL: url)
        guard url != subscriptions[index].requestURL else {
            rename(id, to: name)
            return false
        }
        if let other = subscriptions.first(where: { $0.id == url }) {
            throw ClashTVSubscriptionEditError.addressAlreadyRemembered(other.title)
        }
        subscriptions[index] = ClashTVSubscription(
            requestURL: url,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: nil,
            rules: subscriptions[index].rules,
            scriptURL: subscriptions[index].scriptURL, updateIntervalHours: subscriptions[index].updateIntervalHours
        )
        if chosenID == id { chosenID = url }
        persist()
        return true
    }

     
     
     
     
    mutating func adoptPanelName(_ id: ClashTVSubscription.ID, _ panelName: String?) {
        guard let panelName, !panelName.isEmpty,
              let index = subscriptions.firstIndex(where: { $0.id == id }),
              subscriptions[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let others = subscriptions.enumerated().filter { $0.offset != index }.map { $0.element.title }
        let existing = subscriptions[index]
        subscriptions[index] = ClashTVSubscription(
            requestURL: existing.requestURL,
            name: PanelName.deduplicated(panelName, existing: others),
            updatedAt: existing.updatedAt,
            restored: existing.restored,
            rules: existing.rules,
            scriptURL: existing.scriptURL, updateIntervalHours: existing.updateIntervalHours
        )
        persist()
    }

     
     
    mutating func markUpdated(_ id: ClashTVSubscription.ID, at date: Date) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        let existing = subscriptions[index]
        subscriptions[index] = ClashTVSubscription(
            requestURL: existing.requestURL, name: existing.name, updatedAt: date, restored: existing.restored,
            rules: existing.rules, scriptURL: existing.scriptURL, updateIntervalHours: existing.updateIntervalHours
        )
        persist()
    }

     
     
     
     
    mutating func restore(_ item: ClashTVSubscription) {
        if let index = subscriptions.firstIndex(where: { $0.id == item.id }) {
            subscriptions[index] = ClashTVSubscription(
                requestURL: item.requestURL,
                name: item.name,
                updatedAt: subscriptions[index].updatedAt,
                restored: item.restored,
                rules: subscriptions[index].rules,
                scriptURL: subscriptions[index].scriptURL, updateIntervalHours: subscriptions[index].updateIntervalHours
            )
        } else {
            subscriptions.append(item)
        }
        persist()
    }

     
    var followingAutoBackup: [ClashTVSubscription] {
        subscriptions.filter { $0.restored?.followsAutoBackup == true }
    }

     
     
    mutating func remove(_ id: ClashTVSubscription.ID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions.remove(at: index)
        if chosenID == id { chosenID = nil }
        persist()
    }

     
     
     
     
     
     
     
     
    static func emptyStage() -> ClashTVSubscriptionStore {
        let suite = "clash.tv.stage.empty"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ClashTVSubscriptionStore(defaults: defaults)
    }

    static func stageFixture() -> ClashTVSubscriptionStore {
        let suite = "clash.tv.stage.subscriptions"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var store = ClashTVSubscriptionStore(defaults: defaults)
         
         
        try? store.add(urlString: "https://sub.example.com/clash/home", name: "Home", rules: .defaultRules)
        try? store.add(urlString: "https://example.net/api/v1/client/subscribe", name: "", rules: .lazyRules)
        try? store.add(urlString: "https://backup.example.com/sub", name: "Backup line", rules: .own)
        store.use(URL(string: "https://sub.example.com/clash/home")!)
        return store
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            defaults.set(data, forKey: Self.key)
        }
        if let chosenID {
            defaults.set(chosenID.absoluteString, forKey: Self.currentKey)
        } else {
            defaults.removeObject(forKey: Self.currentKey)
        }
    }
}

 
 
 
 
 
enum ClashTVSubscriptionUpdatedWords {
    static func text(updatedAt: Date?, now: Date = Date()) -> String {
        guard let updatedAt else {
            return String(localized: "Not yet updated")
        }
        if now.timeIntervalSince(updatedAt) < 60 {
            return String(localized: "Updated just now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return String(localized: "Updated \(formatter.localizedString(for: updatedAt, relativeTo: now))")
    }
}
