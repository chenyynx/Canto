import Foundation
import SwiftUI

 
 
 
public enum ClashStorageArea: String, CaseIterable, Codable, Identifiable, Sendable {
    case configurations
    case library
    case geodata
    case providerCaches
    case compiledGeodata
    case logs
    case temporary
     
     
     
     
    case other

    public var id: Self { self }

    public var title: String {
        switch self {
        case .configurations: "Configurations"
        case .library: "Node & Rule Library"
        case .geodata: "Geo Data"
        case .providerCaches: "Rule Set & Node Set Cache"
        case .compiledGeodata: "Compiled Geo Data"
        case .logs: "Logs"
        case .temporary: "Temporary Files"
        case .other: "Other"
        }
    }

     
     
     
     
     
    public var unreclaimableReason: String? {
        switch self {
        case .library: "The library removes its own unused data whenever it is written."
        case .providerCaches: "The core clears this cache each time it starts."
        case .other: "The core's own working files and the downloaded dashboard."
        case .configurations, .geodata, .compiledGeodata, .logs, .temporary: nil
        }
    }
}

public struct ClashStorageRow: Codable, Equatable, Identifiable, Sendable {
    public let area: ClashStorageArea
     
    public let bytes: Int64
     
    public let reclaimable: Int64

    public var id: ClashStorageArea { area }

    public init(area: ClashStorageArea, bytes: Int64, reclaimable: Int64) {
        self.area = area
        self.bytes = bytes
        self.reclaimable = reclaimable
    }
}

public struct ClashStorageSnapshot: Codable, Equatable, Sendable {
    public var rows: [ClashStorageRow]
     
     
    public var tunnelIsRunning: Bool

    public init(rows: [ClashStorageRow], tunnelIsRunning: Bool) {
        self.rows = rows
        self.tunnelIsRunning = tunnelIsRunning
    }

    public var totalBytes: Int64 { rows.reduce(0) { $0 + $1.bytes } }
    public var reclaimableBytes: Int64 { rows.reduce(0) { $0 + $1.reclaimable } }
}

 
 
 
public struct ClashStorageCapabilities: Sendable {
    public typealias Measure = @Sendable () async -> ClashStorageSnapshot
     
     
    public typealias Reclaim = @Sendable (Set<ClashStorageArea>) async throws -> Int64
    public typealias Reset = @Sendable () async throws -> Void

    public let measure: Measure
    public let reclaim: Reclaim
    public let reset: Reset?

    public init(measure: @escaping Measure, reclaim: @escaping Reclaim, reset: Reset? = nil) {
        self.measure = measure
        self.reclaim = reclaim
        self.reset = reset
    }
}

 
 
 
 
 
 
public struct ClashStorageView: View {
    @Environment(\.locale) private var locale
    private let capabilities: ClashStorageCapabilities
     
     
     
    private let liveTunnelIsRunning: Bool?

    @State private var snapshot: ClashStorageSnapshot?
    @State private var isWorking = false
    @State private var freed: Int64?
     
    @State private var freedByArea: [ClashStorageArea: Int64] = [:]
    @State private var didReset = false
    @State private var failure: String?
     
     
    @State private var resetFailure: String?
    @State private var confirmingReset = false

    public init(capabilities: ClashStorageCapabilities, tunnelIsRunning: Bool? = nil) {
        self.capabilities = capabilities
        self.liveTunnelIsRunning = tunnelIsRunning
    }

    private var tunnelIsRunning: Bool {
        liveTunnelIsRunning ?? snapshot?.tunnelIsRunning ?? false
    }

    public var body: some View {
         
         
         
         
        ClashMacSettingsContainer {
            ClashSection("On This Device") {
                HStack {
                    Text(clash: .copy("Total"))
                    Spacer()
                    Text(verbatim: Self.formatted(snapshot?.totalBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("storage.total")
                ForEach(snapshot?.rows ?? []) { row in
                    storageRow(row)
                }
            }

            ClashSection("Clean Up") {
                 
                 
                 
                if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                    HStack(spacing: ClashTheme.Spacing.compact) {
                        Button {
                            Task { await reclaim(Set(ClashStorageArea.allCases)) }
                        } label: {
                            Text(clash: .copy("Clean Up Unused Data"))
                        }
                        .clashMacFormActionChrome()
                        .disabled(isWorking || (snapshot?.reclaimableBytes ?? 0) == 0)
                        .accessibilityIdentifier("storage.reclaim")
                        Text(clash: reclaimableLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    Button {
                        Task { await reclaim(Set(ClashStorageArea.allCases)) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clash: .copy("Clean Up Unused Data"))
                            Text(clash: reclaimableLine)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isWorking || (snapshot?.reclaimableBytes ?? 0) == 0)
                    .accessibilityIdentifier("storage.reclaim")
                }
                if let freed {
                    Text(clash: .format("Freed %@", [Self.formatted(freed)]))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("storage.reclaim.echo")
                }
                if let failure {
                    Text(verbatim: failure)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("storage.failure")
                }
            } footer: {
                Text(clash: .copy(
                    "Removes configurations no longer listed, superseded revisions and downloads, log files from earlier days, and temporary files. Data any configuration still uses is never touched."
                ))
            }

            if capabilities.reset != nil {
                 
                 
                 
                 
                 
                 
                 
                ClashSection("Reset Local Data") {
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        ClashMacFormDestructiveLabel(.copy("Reset Local Data…"))
                    }
                    .clashMacFormDestructiveActionChrome()
                    .disabled(isWorking || tunnelIsRunning)
                    .accessibilityIdentifier("storage.reset")
                    if didReset {
                        Text(clash: .copy("Local data was reset."))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("storage.reset.echo")
                    }
                    if let resetFailure {
                        Text(verbatim: resetFailure)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("storage.reset.failure")
                    }
                } footer: {
                    Text(clash: .copy(
                        tunnelIsRunning
                            ? "Disconnect first to reset local data."
                            : "Deletes every configuration, setting, and stored credential on this device. The VPN configuration in Settings and your iCloud backups stay."
                    ))
                }
            }
        }
        .clashGroupedList()
        .task { await refresh() }
        .onChange(of: liveTunnelIsRunning) { _ in Task { await refresh() } }
        .confirmationDialog(
            Text(clash: .copy("Reset Local Data?")),
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await reset() }
            } label: {
                Text(clash: .copy("Reset Local Data"))
            }
            Button(role: .cancel) {} label: {
                Text(clash: .copy("Cancel"))
            }
        } message: {
            Text(clash: .copy(
                "Deletes every configuration, setting, and stored credential on this device. The VPN configuration in Settings and your iCloud backups stay. Clash starts over as on first launch."
            ))
        }
    }

     
     
     
     
     
     
    @ViewBuilder
    private func storageRow(_ row: ClashStorageRow) -> some View {
        let area = row.area.rawValue
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(clash: .copy(row.area.title))
                Spacer()
                Text(verbatim: Self.formatted(row.bytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("storage.row.\(area)")
            if row.reclaimable > 0 {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    Text(clash: .format("%@ can be freed", [Self.formatted(row.reclaimable)]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await reclaim([row.area]) }
                    } label: {
                        Text(clash: .copy("Clean Up"))
                            .font(.footnote)
                    }
                     
                     
                     
                     
                     
                    .clashMacFormActionChrome()
                    .buttonStyle(.borderless)
                    .disabled(isWorking)
                    .accessibilityIdentifier("storage.row.\(area).reclaim")
                }
            } else if row.bytes > 0, let reason = unreclaimableReason(for: row) {
                Text(clash: .copy(reason))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let freed = freedByArea[row.area] {
                Text(clash: .format("Freed %@", [Self.formatted(freed)]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("storage.row.\(area).echo")
            }
        }
    }

     
     
    private func unreclaimableReason(for row: ClashStorageRow) -> String? {
        if row.area == .compiledGeodata, tunnelIsRunning {
            return "Disconnect first to clean up compiled geo data."
        }
        return row.area.unreclaimableReason
    }

    private var reclaimableLine: ClashDisplayText {
        let reclaimable = snapshot?.reclaimableBytes ?? 0
        return reclaimable > 0
            ? .format("%@ can be freed", [Self.formatted(reclaimable)])
            : .copy("Nothing to clean up")
    }

    private func refresh() async {
        snapshot = await capabilities.measure()
    }

    private func reclaim(_ areas: Set<ClashStorageArea>) async {
        isWorking = true
        defer { isWorking = false }
        failure = nil
        do {
            let went = try await capabilities.reclaim(areas)
            if areas.count == 1, let area = areas.first {
                freedByArea[area] = went
            } else {
                freed = went
                freedByArea = [:]
            }
        } catch {
            failure = ClashErrorCopy.message(error, locale: locale)
        }
        await refresh()
    }

    private func reset() async {
        guard let reset = capabilities.reset else { return }
        isWorking = true
        defer { isWorking = false }
        resetFailure = nil
        do {
            try await reset()
            didReset = true
        } catch {
            resetFailure = ClashErrorCopy.message(error, locale: locale)
        }
        await refresh()
    }

     
     
    static func formatted(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
