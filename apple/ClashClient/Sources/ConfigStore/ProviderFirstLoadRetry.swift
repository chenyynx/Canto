import Foundation
import ClashClientUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProviderFirstLoadRetry {
    enum Trigger: String { case activation, connected, scan }

    struct Outcome: Equatable {
        var attempted = 0
        var updated = 0
        var failed = 0
        var skippedInFlight = 0
         
        var skippedLoadedInCore = 0
         
        var skippedBackingOff = 0
    }

     

     
     
     
     
     
     
     
     
     
     
     
     
     
    final class Backoff: @unchecked Sendable {
        private struct Record { var failures: Int; var last: Date; var tunnelUp: Bool }
        private let lock = NSLock()
        private var records: [String: Record] = [:]
        static let capacity = 256
        static let forgottenAfter: TimeInterval = 2 * 3_600

        static func key(container: URL, profileID: String, entry: ProviderCatalog.Entry) -> String {
            [container.path, profileID, entry.name, entry.requestFingerprint ?? entry.url].joined(separator: "\n")
        }

        var count: Int { lock.lock(); defer { lock.unlock() }; return records.count }

        func resetForTesting() {
            lock.lock(); records = [:]; lock.unlock()
        }

        static func delay(afterFailures failures: Int) -> TimeInterval {
            min(60 * pow(2, Double(max(0, failures - 1))), 3_600)
        }

        func holds(_ key: String, now: Date, tunnelUp: Bool) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let record = records[key], !(tunnelUp && !record.tunnelUp) else { return false }
            return now < record.last.addingTimeInterval(Self.delay(afterFailures: record.failures))
        }

        func failed(_ keys: [String], at now: Date, tunnelUp: Bool) {
            lock.lock(); defer { lock.unlock() }
            records = records.filter { now.timeIntervalSince($0.value.last) < Self.forgottenAfter }
            for key in keys {
                var record = records[key] ?? Record(failures: 0, last: now, tunnelUp: tunnelUp)
                 
                if tunnelUp && !record.tunnelUp { record.failures = 0 }
                record.failures += 1
                record.last = now
                record.tunnelUp = tunnelUp
                records[key] = record
            }
            if records.count > Self.capacity {
                let oldest = records.sorted { $0.value.last < $1.value.last }.prefix(records.count - Self.capacity)
                for (key, _) in oldest { records.removeValue(forKey: key) }
            }
        }

        func succeeded(_ keys: [String]) {
            lock.lock(); defer { lock.unlock() }
            for key in keys { records.removeValue(forKey: key) }
        }
    }

    static let backoff = Backoff()

     
     
     
     
     
     
     
     
     
    nonisolated(unsafe) static var loadedRuleProvidersInCore: (@Sendable () async -> Set<String>)?

     
     
     
    nonisolated(unsafe) static var loadedProxyProvidersInCore: (@Sendable () async -> Set<String>)?

     
     
     
    static let didRefreshNotification = Notification.Name("org.example.canto.provider.first-load.refreshed")

     
     
     
     
     
     
    static func select(entries: [ProviderCatalog.Entry]) -> [ProviderCatalog.Entry] {
        entries.filter { entry in
            entry.lastUpdatedAt == nil
                && (entry.kind == "rule" || (entry.kind == "proxy" && (entry.count ?? 0) == 0))
        }
    }

     
     
    static func select(
        entries: [ProviderCatalog.Entry], loadedInCore: Set<String>,
        loadedProxiesInCore: Set<String> = [],
        routeSetProviders: Set<String> = [], coreFetchedProviders: Set<String> = [],
        providersDir: URL? = nil, coreOwnedRouteWork: Set<String> = []
    ) -> [ProviderCatalog.Entry] {
        entries.filter { entry in
            if entry.kind == "proxy" {
                 
                 
                 
                return entry.lastUpdatedAt == nil && (entry.count ?? 0) == 0
                    && !coreFetchedProviders.contains(entry.name)
                    && !loadedProxiesInCore.contains(entry.name)
            }
            guard entry.kind == "rule" else { return false }
            if coreFetchedProviders.contains(entry.name) {
                return routeSetProviders.contains(entry.name) && coreOwnedRouteWork.contains(entry.name)
            }
            if routeSetProviders.contains(entry.name) {
                let missing = providersDir.map { directory in
                    let attributes = try? FileManager.default.attributesOfItem(
                        atPath: directory.appendingPathComponent(entry.path).path)
                    return attributes?[.type] as? FileAttributeType != .typeRegular
                        || ((attributes?[.size] as? NSNumber)?.intValue ?? 0) <= 0
                } ?? (entry.lastUpdatedAt == nil)
                if missing || entry.lastUpdatedAt == nil { return true }
            }
            return entry.lastUpdatedAt == nil && !loadedInCore.contains(entry.name)
        }
    }

     
     
     
     
    static func budget(for trigger: Trigger, tunnelUp: Bool) -> ProviderFetchBudget {
        .patient
    }

     

    final class InFlight: @unchecked Sendable {
        private let lock = NSLock()
        private var names: Set<String> = []

         
        func claim(_ wanted: [String]) -> (claimed: [String], busy: Int) {
            lock.lock(); defer { lock.unlock() }
            var claimed: [String] = []
            var busy = 0
            for name in wanted {
                if names.contains(name) { busy += 1 } else { names.insert(name); claimed.append(name) }
            }
            return (claimed, busy)
        }

        func release(_ done: [String]) {
            lock.lock(); defer { lock.unlock() }
            for name in done { names.remove(name) }
        }

        var count: Int { lock.lock(); defer { lock.unlock() }; return names.count }
    }

    static let inFlight = InFlight()

     
     
     
     
     
     
    private static let rerunLock = NSLock()
    nonisolated(unsafe) private static var rerunAfterInFlight = false

    static func requestRerunAfterInFlight() {
        rerunLock.lock(); rerunAfterInFlight = true; rerunLock.unlock()
    }

    static func takeRerunRequest() -> Bool {
        rerunLock.lock(); defer { rerunLock.unlock() }
        let requested = rerunAfterInFlight
        rerunAfterInFlight = false
        return requested
    }

     

    private static let updatesLock = NSLock()
    nonisolated(unsafe) private static var pendingUpdates: [ProviderRuntimeUpdate] = []

    static func takeRuntimeUpdates() -> [ProviderRuntimeUpdate] {
        updatesLock.lock(); defer { updatesLock.unlock() }
        let taken = pendingUpdates
        pendingUpdates = []
        return taken
    }

    private static func enqueue(_ update: ProviderRuntimeUpdate) {
        updatesLock.lock()
        pendingUpdates.append(update)
        updatesLock.unlock()
    }

     

     
     
    nonisolated(unsafe) static var scheduler: (Trigger) -> Void = { trigger in
        Task.detached(priority: .utility) {
            _ = await run(trigger: trigger)
        }
    }

     
     
    static func noteActivation(pending: [String], profileID: String) {
        guard !pending.isEmpty else { return }
        ClashLogStore.shared.append(
            "provider first-load: \(pending.count) provider(s) still need local materialization; retry scheduled  profile=\(profileID)",
            stream: .app, level: .info
        )
        scheduler(.activation)
    }

    static func kick(trigger: Trigger) {
        scheduler(trigger)
    }

     
     
    static func tunnelIsUp(container: URL) -> Bool {
        ClashWidgetMailboxStore(root: container).readSnapshot()?.phase == .connected
    }

     
     
    static func recoverCoreOwnedRoutesBeforeStart(
        container: URL, coordinator suppliedCoordinator: ProfileActivationCoordinator? = nil
    ) async throws {
        do {
            try Task.checkCancellation()
            let store = try ConfigResourceStore(containerURL: container)
            guard let expected = try store.activePointer() else { return }
            let working = container.appendingPathComponent("working")
            let profiles = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
            guard let profile = profiles.load().first(where: { $0.id == expected.profileID }) else { return }
            let coordinator = suppliedCoordinator ?? ProfileActivationCoordinator(
                store: store, profileStore: profiles, credentials: CredentialStore(),
                downloader: ResourceDownloader(), coreHomeDir: working,
                compileRuleSets: false, activator: { _ in })
            let names = try coordinator.coreOwnedRouteRecoveryNames(profile: profile, current: expected)
            guard !names.isEmpty else { return }
            _ = try await coordinator.refreshPendingProviders(profile: profile, names: Array(names),
                fetchBudget: .activation, expectedActive: expected)
            try Task.checkCancellation()
        } catch is CancellationError { throw CancellationError() }
        catch {
             
             
            ClashLogStore.shared.append("core route cache recovery: \(error.localizedDescription)", stream: .app, level: .warning)
        }
    }

     
    @discardableResult
    static func run(
        trigger: Trigger,
        container: URL? = ClashAppIdentifiers.appGroupContainer,
        tunnelUp: Bool? = nil,
        now: Date = Date(),
         
        downloader suppliedDownloader: HTTPFetching? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) async -> Outcome {
        var outcome = Outcome()
        guard let container,
              let store = try? ConfigResourceStore(containerURL: container),
              let active = try? store.activePointer(),
              let providersDir = try? store.activeProvidersDirectory(),
              var catalog = ProviderCatalog.load(providersDir: providersDir)
        else { return outcome }
        let working = container.appendingPathComponent("working")
        let profileStore = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
        guard let profile = profileStore.load().first(where: { $0.id == active.profileID }) else { return outcome }

        let credentials = CredentialStore()
        let downloader = suppliedDownloader ?? ResourceDownloader()
         
         
         
        let coordinator = ProfileActivationCoordinator(
            store: store, profileStore: profileStore, credentials: credentials,
            downloader: downloader, coreHomeDir: working,
            compileRuleSets: false, activator: { _ in }, now: { now }
        )
        if catalog.routeSetProviders == nil || catalog.coreFetchedProviders == nil {
            do {
                let inferred = try coordinator.providerRetryCatalog(profile: profile)
                catalog.routeSetProviders = inferred.routeSetProviders
                catalog.coreFetchedProviders = inferred.coreFetchedProviders
            } catch {
                ClashLogStore.shared.append(
                    "provider first-load: effective legacy metadata unavailable  \(error.localizedDescription)",
                    stream: .app, level: .info)
                return outcome
            }
        }
        let up = tunnelUp ?? tunnelIsUp(container: container)
        var loadedInCore: Set<String> = []
        if up, let probe = loadedRuleProvidersInCore {
            loadedInCore = await probe()
        }
        var loadedProxiesInCore: Set<String> = []
        if up, let probe = loadedProxyProvidersInCore {
            loadedProxiesInCore = await probe()
        }
        let coreOwnedRouteWork = (try? coordinator.coreOwnedRouteRecoveryNames(profile: profile, current: active)) ?? []
        let owed = select(entries: catalog.entries)
        var wanted = select(
            entries: catalog.entries, loadedInCore: loadedInCore,
            loadedProxiesInCore: loadedProxiesInCore,
            routeSetProviders: catalog.routeSetProviders ?? [],
            coreFetchedProviders: catalog.coreFetchedProviders ?? [], providersDir: providersDir,
            coreOwnedRouteWork: coreOwnedRouteWork).map(\.name)
        outcome.skippedLoadedInCore = owed.filter {
            ($0.kind == "proxy" ? loadedProxiesInCore : loadedInCore).contains($0.name) && !wanted.contains($0.name)
                && !(catalog.coreFetchedProviders ?? []).contains($0.name)
        }.count
        if outcome.skippedLoadedInCore > 0 {
            ClashLogStore.shared.append(
                "provider first-load: the core already loaded \(outcome.skippedLoadedInCore) provider(s); not fetching those",
                stream: .app, level: .info
            )
        }
        func backoffKey(_ name: String) -> String {
            catalog.entries.first { $0.name == name }
                .map { Backoff.key(container: container, profileID: active.profileID, entry: $0) } ?? name
        }
        let startedAt = clock()
        let backingOff = wanted.filter { backoff.holds(backoffKey($0), now: startedAt, tunnelUp: up) }
        outcome.skippedBackingOff = backingOff.count
        wanted.removeAll { backingOff.contains($0) }
        if !backingOff.isEmpty {
            ClashLogStore.shared.append(
                "provider first-load: \(backingOff.count) provider(s) failed recently; trying again later",
                stream: .app, level: .info
            )
        }
        guard !wanted.isEmpty else { return outcome }
        var (claimed, busy) = inFlight.claim(wanted)
         
         
         
         
        let addressOf = Dictionary(catalog.entries.map { ($0.name, $0.url) }, uniquingKeysWith: { first, _ in first })
        let heldAddresses = ProviderDownloadActivity.claim(Array(Set(claimed.compactMap { addressOf[$0] })))
        let blocked = claimed.filter { name in addressOf[name].map { !heldAddresses.contains($0) } ?? false }
        if !blocked.isEmpty {
            inFlight.release(blocked)
            claimed.removeAll { blocked.contains($0) }
            busy += blocked.count
        }
        outcome.skippedInFlight = busy
        if busy > 0, trigger == .connected { requestRerunAfterInFlight() }
        guard !claimed.isEmpty else {
            ProviderDownloadActivity.release(heldAddresses)
            return outcome
        }
        defer {
            inFlight.release(claimed)
            ProviderDownloadActivity.release(heldAddresses)
            if takeRerunRequest() {
                Task.detached(priority: .utility) { _ = await run(trigger: .connected, container: container, now: Date()) }
            }
        }

        let budget = budget(for: trigger, tunnelUp: up)
        ClashLogStore.shared.append(
            "provider first-load: trigger=\(trigger.rawValue) budget=\(budget == .quick ? "quick" : "patient") tunnel=\(up ? "up" : "down") providers=\(claimed.count) busy=\(busy)",
            stream: .app, level: .info
        )
        var refreshed = 0
        var failed = claimed.count
         
         
        let addresses = Dictionary(
            catalog.entries.filter { claimed.contains($0.name) }.map { ($0.name, $0.url) },
            uniquingKeysWith: { first, _ in first })
        ProviderDownloadActivity.begin(Array(addresses.values))
        var reasons: [String: ProviderNote?] = addresses.mapValues { _ in nil }
         
         
        var answered = Set(addresses.keys)
        defer {
            for (name, url) in addresses {
                ProviderDownloadActivity.end(url, failure: reasons[name] ?? nil, answered: answered.contains(name))
            }
        }
        do {
             
             
             
             
            let round = try await coordinator.refreshPendingProviders(
                profile: profile, names: claimed, fetchBudget: budget, expectedActive: active
            )
            if !round.stillPending.isEmpty,
               let published = store.providersDirectory(profileID: round.pointer.profileID, revision: round.pointer.revision),
               let recorded = ProviderCatalog.load(providersDir: published) {
                for name in round.stillPending {
                    reasons[name] = recorded.entries.first { $0.name == name }?.note
                }
            }
            for update in round.runtimeUpdates.values
            where !round.publishedRouteNames.contains(update.name) {
                enqueue(update)
            }
             
             
             
             
             
             
            let cameDown = Set(round.runtimeUpdates.keys).union(round.publishedRouteNames)
            refreshed = cameDown.count
            failed = claimed.count - refreshed
            backoff.succeeded(claimed.filter { cameDown.contains($0) }.map(backoffKey))
             
             
             
            backoff.failed(claimed.filter { !cameDown.contains($0) }.map(backoffKey), at: clock(), tunnelUp: up)
        } catch {
             
             
             
             
             
             
            ClashLogStore.shared.append(
                "provider first-load: round not published  \(error.localizedDescription)",
                stream: .app, level: .info
            )
            answered = []
            for (name, reason) in Self.providerAnswers(to: error, addresses: addresses) {
                reasons[name] = reason
                answered.insert(name)
            }
            backoff.failed(Array(answered).map(backoffKey), at: clock(), tunnelUp: up)
        }
        outcome.attempted = claimed.count
        outcome.updated = refreshed
        outcome.failed = failed
        if refreshed > 0 {
            NotificationCenter.default.post(name: didRefreshNotification, object: nil)
        }
        ClashLogStore.shared.append(
            "provider first-load: done trigger=\(trigger.rawValue) refreshed=\(refreshed) pending=\(failed)",
            stream: .app, level: .info
        )
        return outcome
    }

     
     
     
     
    static func providerAnswers(to error: Error, addresses: [String: String]) -> [String: ProviderNote] {
        var answers: [String: ProviderNote] = [:]
        if let batch = error as? ProviderDownloadFailuresError {
            for failure in batch.failures {
                guard let url = addresses[failure.provider] else { continue }
                answers[failure.provider] = ProviderDownloadActivity.reason(
                    for: ProviderDownloadFailuresError(failures: [failure]), url: url)
            }
        } else if let refused = error as? ProviderValidationFailure, let url = addresses[refused.provider] {
            answers[refused.provider] = ProviderDownloadActivity.reason(for: refused, url: url)
        } else if let refusal = error as? MaterializeError, refusal.providerRowText != nil,
                  let url = addresses[refusal.provider] {
            answers[refusal.provider] = ProviderDownloadActivity.reason(for: refusal, url: url)
        }
        return answers
    }
}
