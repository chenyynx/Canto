import Foundation
import ClashClientUI
import SwiftUI

 
 
 
 
struct StorageView: View {
    @ObservedObject var vpn: VPNController
    @ObservedObject var command: ClashCommandClient
    @ObservedObject var preferences: AppPreferencesModel

    var body: some View {
        ClashStorageView(capabilities: capabilities, tunnelIsRunning: Self.tunnelIsRunning(vpn.status))
    }

    private var capabilities: ClashStorageCapabilities {
        let vpn = vpn, command = command, preferences = preferences
        return ClashStorageCapabilities(
            measure: {
                let running = await MainActor.run { Self.tunnelIsRunning(vpn.status) }
                return await Task.detached(priority: .utility) {
                    Self.snapshot(tunnelIsRunning: running)
                }.value
            },
            reclaim: { areas in
                let running = await MainActor.run { Self.tunnelIsRunning(vpn.status) }
                let engineAreas = Set(areas.compactMap(Self.engineArea))
                return try await Task.detached(priority: .utility) { () throws -> Int64 in
                    guard let engine = Self.engine(tunnelIsRunning: { running }) else { return 0 }
                    return try engine.reclaim(engineAreas).reclaimedBytes
                }.value
            },
            reset: {
                try await Self.resetLocalData(vpn: vpn, command: command, preferences: preferences)
            }
        )
    }

     

    static func tunnelIsRunning(_ status: String) -> Bool {
        ["connected", "connecting", "reasserting", "disconnecting"].contains(status)
    }

    private static func engine(tunnelIsRunning: @escaping () -> Bool) -> StorageMaintenance? {
        guard let container = ClashAppIdentifiers.appGroupContainer else { return nil }
        return StorageMaintenance(containerURL: container, tunnelIsRunning: tunnelIsRunning)
    }

     
     
     
    static func snapshot(tunnelIsRunning: Bool) -> ClashStorageSnapshot {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let engine = engine(tunnelIsRunning: { tunnelIsRunning }) else {
            return ClashStorageSnapshot(rows: [], tunnelIsRunning: tunnelIsRunning)
        }
        let measured = engine.measure()
        var rows = measured.map { ClashStorageRow(area: Self.area($0.area), bytes: $0.bytes, reclaimable: $0.reclaimable) }
        let containerBytes = StorageMeasurement.allocatedBytes(at: container)
        let accounted = measured.reduce(0) { $0 + $1.bytes }
        rows.append(ClashStorageRow(area: .other, bytes: max(0, containerBytes - accounted), reclaimable: 0))
        return ClashStorageSnapshot(rows: rows, tunnelIsRunning: tunnelIsRunning)
    }

    static func area(_ area: StorageMaintenance.Area) -> ClashStorageArea {
        switch area {
        case .configurations: .configurations
        case .library: .library
        case .geodata: .geodata
        case .providerCaches: .providerCaches
        case .compiledGeodata: .compiledGeodata
        case .logs: .logs
        case .temporary: .temporary
        }
    }

     
    static func engineArea(_ area: ClashStorageArea) -> StorageMaintenance.Area? {
        switch area {
        case .configurations: .configurations
        case .library: .library
        case .geodata: .geodata
        case .providerCaches: .providerCaches
        case .compiledGeodata: .compiledGeodata
        case .logs: .logs
        case .temporary: .temporary
        case .other: nil
        }
    }

     

    enum ResetError: LocalizedError {
        case tunnelStillRunning
        case unavailable
        var errorDescription: String? {
            switch self {
            case .tunnelStillRunning: "Disconnect first to reset local data."
            case .unavailable: "Local data is unavailable."
            }
        }
    }

     
     
     
     
     
    @MainActor
    static func resetLocalData(vpn: VPNController, command: ClashCommandClient, preferences: AppPreferencesModel) async throws {
        guard let manager = DeveloperDataManager(), let container = ClashAppIdentifiers.appGroupContainer else {
            throw ResetError.unavailable
        }
        if tunnelIsRunning(vpn.status) {
            await vpn.stop()
            var waited = 0
            while tunnelIsRunning(vpn.status), waited < 300 {
                try await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            guard !tunnelIsRunning(vpn.status) else { throw ResetError.tunnelStillRunning }
        }
        command.disconnect()
        try manager.resetAllLocalData()
        preferences.resetToDefaults()
        let working = container.appendingPathComponent("working", isDirectory: true)
        try LocalDefaultProfileProvisioner.provisionIfNeeded(
            store: ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json")),
            workingDirectory: working
        )
    }
}
