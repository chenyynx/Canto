import Combine
import Foundation
import ClashClientKit

 
 
 
 
 
public enum ClashProxyRuntimeCatalogPhase:
    String,
    Equatable,
    Sendable
{
    case disconnected
    case loading
    case ready
    case failed
}

public struct ClashProxyRuntimeNodeSnapshot:
    Equatable,
    Identifiable,
    Sendable
{
    public var name: String
    public var type: String
    public var delayMilliseconds: Int?
    public var latencyFreshness: LatencyProbeFreshness

    public var id: String { name }

    public init(
        name: String,
        type: String,
        delayMilliseconds: Int? = nil,
        latencyFreshness: LatencyProbeFreshness? = nil
    ) {
         
         
         
        self.name = name
        self.type = String(type.prefix(256))
        let boundedDelay = delayMilliseconds.flatMap {
            (0...3_600_000).contains($0) ? $0 : nil
        }
        self.delayMilliseconds = boundedDelay
        self.latencyFreshness = latencyFreshness ?? {
            guard let boundedDelay else { return .neverTested }
            return boundedDelay > 0 ? .stale : .failed
        }()
    }
}

public struct ClashProxyRuntimeGroupSnapshot:
    Equatable,
    Identifiable,
    Sendable
{
    public var name: String
    public var type: String
    public var currentName: String?
    public var members: [ClashProxyRuntimeNodeSnapshot]

    public var id: String { name }
    public var isSelectable: Bool {
        type.caseInsensitiveCompare("Selector") == .orderedSame
    }

    public init(
        name: String,
        type: String,
        currentName: String? = nil,
        members: [ClashProxyRuntimeNodeSnapshot]
    ) {
         
         
         
        self.name = name
        self.type = String(type.prefix(256))
         
         
        self.currentName = currentName.flatMap { value in
            members.contains(where: { $0.name == value }) ? value : nil
        }
        self.members = members
    }
}

public struct ClashProxyLatencySweepSnapshot:
    Equatable,
    Sendable
{
    public var isRunning: Bool
    public var completedCount: Int
    public var totalCount: Int
    public var testingNames: Set<String>

    public init(
        isRunning: Bool,
        completedCount: Int,
        totalCount: Int,
        testingNames: Set<String>
    ) {
        let boundedTotal = max(0, totalCount)
        self.isRunning = isRunning
        self.completedCount = min(
            max(0, completedCount),
            boundedTotal
        )
        self.totalCount = boundedTotal
        self.testingNames = Set(
            testingNames.prefix(
                LatencyProbePolicy.macOS.maxConcurrentProbes
                    + LatencyProbePolicy.macOS.maxConcurrentProbes
            )
        )
    }

    public static let idle = ClashProxyLatencySweepSnapshot(
        isRunning: false,
        completedCount: 0,
        totalCount: 0,
        testingNames: []
    )
}

public struct ClashProxyLatencyResult:
    Equatable,
    Sendable
{
    public let delayMilliseconds: Int
    public let freshness: LatencyProbeFreshness

    public init(outcome: LatencyProbeOutcome) {
        switch outcome {
        case .success(let milliseconds):
            if (1...3_600_000).contains(milliseconds) {
                delayMilliseconds = milliseconds
                freshness = .fresh
            } else {
                delayMilliseconds = 0
                freshness = .failed
            }
        case .failure:
            delayMilliseconds = 0
            freshness = .failed
        case .deferred:
             
             
            delayMilliseconds = 0
            freshness = .neverTested
        }
    }
}

public struct ClashProxiesRuntimeSnapshot:
    Equatable,
    Sendable
{
    public var phase: ClashProxyRuntimeCatalogPhase
    public var groups: [ClashProxyRuntimeGroupSnapshot]
    public var nodes: [ClashProxyRuntimeNodeSnapshot]
    public var latencySweep: ClashProxyLatencySweepSnapshot
    public var errorDescription: String?

    public var selectableGroupCount: Int {
        groups.filter(\.isSelectable).count
    }

    public var totalNodeCount: Int {
        Set(
            nodes.map(\.name)
                + groups.flatMap { $0.members.map(\.name) }
        ).count
    }

    public init(
        phase: ClashProxyRuntimeCatalogPhase,
        groups: [ClashProxyRuntimeGroupSnapshot] = [],
        nodes: [ClashProxyRuntimeNodeSnapshot] = [],
        latencySweep: ClashProxyLatencySweepSnapshot = .idle,
        errorDescription: String? = nil
    ) {
        self.phase = phase
        self.groups = groups
        self.nodes = nodes
        self.latencySweep = latencySweep
        self.errorDescription = errorDescription.map {
            String($0.prefix(512))
        }
    }

    public static let disconnected = Self(phase: .disconnected)
    public static let loading = Self(phase: .loading)
    public static let readyEmpty = Self(phase: .ready)

    public static func failed(_ message: String) -> Self {
        Self(phase: .failed, errorDescription: message)
    }
}

public enum ClashProxyLatencyProbePlan {
    public static func make(
        snapshot: ClashProxiesRuntimeSnapshot,
        visibleGroupNames: [String]
    ) -> LatencyProbePlan {
        var freshnessByName:
            [String: LatencyProbeFreshness] = [:]
        let allNodes =
            snapshot.groups.flatMap(\.members) + snapshot.nodes
        for node in allNodes {
            if let previous = freshnessByName[node.name] {
                if node.latencyFreshness.rawValue
                    < previous.rawValue
                {
                    freshnessByName[node.name] =
                        node.latencyFreshness
                }
            } else {
                freshnessByName[node.name] =
                    node.latencyFreshness
            }
        }

        var groups = snapshot.groups.map { group in
            LatencyProbeGroup(
                name: group.name,
                members: group.members.map(\.name),
                selectedName: group.currentName
            )
        }
        if !snapshot.nodes.isEmpty {
            groups.append(
                LatencyProbeGroup(
                    name: "Clash Standalone Nodes",
                    members: snapshot.nodes.map(\.name)
                )
            )
        }
        return LatencyProbePlan(
            groups: groups,
            visibleGroupNames: visibleGroupNames,
            freshnessByName: freshnessByName,
            excludedNames:
                LatencyProbeNamePolicy.probeExcludedNames
        )
    }
}

 
@MainActor
public final class ClashProxyLatencySweepController:
    ObservableObject
{
    @Published public private(set) var snapshot =
        ClashProxyLatencySweepSnapshot.idle
    @Published public private(set) var results:
        [String: ClashProxyLatencyResult] = [:]

    private let policy: LatencyProbePolicy
    private var runID: UInt64 = 0
    private var runTask: Task<Void, Never>?
    private var cancellation: LatencyProbeCancellation?
    private var memoryPressureSource:
        DispatchSourceMemoryPressure?

    public init(
        policy: LatencyProbePolicy = .macOS,
        observesMemoryPressure: Bool = true
    ) {
        self.policy = policy
        guard observesMemoryPressure else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancel(reason: .memoryPressure)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    deinit {
        memoryPressureSource?.cancel()
        runTask?.cancel()
    }

    public func result(
        for name: String
    ) -> ClashProxyLatencyResult? {
        results[name]
    }

    public func start(
        snapshot sourceSnapshot: ClashProxiesRuntimeSnapshot,
        visibleGroupNames: [String],
        probe:
            @escaping @Sendable (String) async
                -> LatencyProbeOutcome
    ) {
        let plan = ClashProxyLatencyProbePlan.make(
            snapshot: sourceSnapshot,
            visibleGroupNames: visibleGroupNames
        )
        let totalCount =
            LatencyProbeScheduler.orderedNames(for: plan).count
        guard totalCount > 0 else {
            snapshot = .idle
            return
        }

        runID &+= 1
        let nextRunID = runID
        let previousTask = runTask
        let previousCancellation = cancellation
        previousTask?.cancel()

        let nextCancellation = LatencyProbeCancellation()
        cancellation = nextCancellation
        snapshot = ClashProxyLatencySweepSnapshot(
            isRunning: true,
            completedCount: 0,
            totalCount: totalCount,
            testingNames: []
        )

        let task = Task { @MainActor [weak self] in
            await previousCancellation?.cancel(
                reason: .superseded
            )
            if let previousTask {
                await previousTask.value
            }
            guard let self, runID == nextRunID else {
                return
            }

            _ = await LatencyProbeScheduler.run(
                runID: nextRunID,
                plan: plan,
                policy: policy,
                cancellation: nextCancellation,
                onEvent: { [weak self] event in
                    await self?.apply(event)
                },
                probe: probe
            )
            guard runID == nextRunID else { return }
            runTask = nil
            cancellation = nil
        }
        runTask = task
    }

    public func cancel(
        reason: LatencyProbeCancellationReason,
        clearResults: Bool = false
    ) {
        runID &+= 1
        let previousTask = runTask
        let previousCancellation = cancellation
        runTask = nil
        cancellation = nil
        previousTask?.cancel()
        snapshot = ClashProxyLatencySweepSnapshot(
            isRunning: false,
            completedCount: snapshot.completedCount,
            totalCount: snapshot.totalCount,
            testingNames: []
        )
        if clearResults {
            results.removeAll(keepingCapacity: false)
        }
        Task {
            await previousCancellation?.cancel(reason: reason)
            if let previousTask {
                await previousTask.value
            }
        }
    }

    private func apply(_ event: LatencyProbeEvent) {
        switch event {
        case .started(let started):
            guard started.runID == runID else { return }
            var testingNames = snapshot.testingNames
            testingNames.insert(started.name)
            snapshot = ClashProxyLatencySweepSnapshot(
                isRunning: true,
                completedCount: max(
                    snapshot.completedCount,
                    started.completedCount
                ),
                totalCount: started.totalCount,
                testingNames: testingNames
            )
        case .result(let result):
            guard result.runID == runID else { return }
            results[result.name] = ClashProxyLatencyResult(
                outcome: result.outcome
            )
            var testingNames = snapshot.testingNames
            testingNames.remove(result.name)
            snapshot = ClashProxyLatencySweepSnapshot(
                isRunning: true,
                completedCount: max(
                    snapshot.completedCount,
                    result.completedCount
                ),
                totalCount: result.totalCount,
                testingNames: testingNames
            )
        case .cancelled(let cancelled):
            guard cancelled.runID == runID else { return }
            var testingNames = snapshot.testingNames
            testingNames.remove(cancelled.name)
            snapshot = ClashProxyLatencySweepSnapshot(
                isRunning: true,
                completedCount: snapshot.completedCount,
                totalCount: snapshot.totalCount,
                testingNames: testingNames
            )
        case .finished(let summary):
            guard summary.runID == runID else { return }
            snapshot = ClashProxyLatencySweepSnapshot(
                isRunning: false,
                completedCount: summary.completedCount,
                totalCount: summary.totalCount,
                testingNames: []
            )
        }
    }
}
