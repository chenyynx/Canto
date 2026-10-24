import Foundation
import NetworkExtension

 
 
 
 
@MainActor
enum IPStackSettingsApplication {
    static func apply(
        _ next: IPStackSettings,
        defaults: UserDefaults,
        saveProtocol: @escaping (IPStackSettings) async throws -> Void,
        restoreProtocol: @escaping () async throws -> Void = {},
        publishPreference: ((IPStackSettings) throws -> Void)? = nil,
        withProfileWrite: (@escaping @MainActor () async throws -> Void) async throws -> Void = { try await $0() },
        isRunning: () -> Bool,
        restart: () async throws -> Void
    ) async throws {
        let previous = try IPStackSettings.load(from: defaults)
        guard next != previous else { return }
        try Task.checkCancellation()
        try await withProfileWrite {
            try await saveProtocol(next)
            do {
                if let publishPreference { try publishPreference(next) }
                else { try next.save(to: defaults) }
            } catch {
                let publicationError = error
                do { try await restoreProtocol() }
                catch {
                    throw IPStackSettingsApplicationError.compensationFailed(
                        publication: publicationError.localizedDescription,
                        restoration: error.localizedDescription)
                }
                throw publicationError
            }
        }
        try Task.checkCancellation()
        if isRunning() { try await restart() }
    }
}


enum IPStackSettingsApplicationError: LocalizedError {
    case operationInProgress
    case compensationFailed(publication: String, restoration: String)

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return String(localized: "A VPN operation is already in progress. Wait for it to finish before changing IP Stack settings.")
        case let .compensationFailed(publication, restoration):
            return String(format: String(localized: "IP Stack preferences could not be saved (%@), and the previous VPN settings could not be restored (%@). The VPN was not restarted."), publication, restoration)
        }
    }
}


 
 
@MainActor
final class IPStackProfileWriter {
    private var tail: Task<Void, Never>?
    private var settingsWritePending = false
    private var pendingOperations = 0
    private(set) var revision: UInt64 = 0
    var isBusy: Bool { pendingOperations > 0 || settingsWritePending }
    private var confirmedSnapshot: IPStackSystemProfileSnapshot?
    private weak var confirmedManager: NETunnelProviderManager?

    func settingsTransaction(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        guard !settingsWritePending else { throw IPStackSettingsApplicationError.operationInProgress }
        settingsWritePending = true
        defer { settingsWritePending = false }
        try await run(operation)
    }

    func requireStartReady() throws {
        guard !settingsWritePending else { throw IPStackSettingsApplicationError.operationInProgress }
    }

    func run(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        try Task.checkCancellation()
        pendingOperations += 1
        revision &+= 1
        defer { pendingOperations -= 1 }
        let predecessor = tail
        let task = Task { @MainActor in
            await predecessor?.value
            try Task.checkCancellation()
            try await operation()
        }
        tail = Task { @MainActor in _ = try? await task.value }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

     
     
     
    func saveConfirmed(
        _ frozen: IPStackSystemProfileSnapshot,
        to manager: NETunnelProviderManager,
        disarmOnly: Bool = false,
        save: () async throws -> Void
    ) async throws {
        let sameManager = confirmedManager === manager
        let base = disarmOnly && sameManager ? (confirmedSnapshot ?? frozen) : frozen
        base.apply(to: manager, disarm: disarmOnly)
        let submitted = IPStackSystemProfileSnapshot(manager)
        try await save()
        confirmedSnapshot = submitted
        confirmedManager = manager
    }

    static func awaitConfirmation(
        operation: () async throws -> Void,
        delay: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 15_000_000_000) },
        onWaiting: @escaping () -> Void
    ) async throws {
        let notice = Task { @MainActor in
            do { try await delay(); try Task.checkCancellation(); onWaiting() }
            catch { }
        }
        defer { notice.cancel() }
        try await operation()
    }
}


 
@MainActor
struct IPStackSystemProfileSnapshot {
    private let configuration: NEVPNProtocol?
    private let enabled: Bool
    private let onDemand: Bool
    private let rules: [NEOnDemandRule]?
    private let title: String?

    init(_ manager: NETunnelProviderManager) {
        configuration = manager.protocolConfiguration?.copy() as? NEVPNProtocol
        enabled = manager.isEnabled
        onDemand = manager.isOnDemandEnabled
        rules = manager.onDemandRules?.map { $0.copy() as! NEOnDemandRule }
        title = manager.localizedDescription
    }

    func apply(to manager: NETunnelProviderManager, disarm: Bool = false) {
        manager.protocolConfiguration = configuration?.copy() as? NEVPNProtocol
        manager.isEnabled = enabled
        manager.isOnDemandEnabled = disarm ? false : onDemand
        manager.onDemandRules = rules?.map { $0.copy() as! NEOnDemandRule }
        manager.localizedDescription = title
    }
}
