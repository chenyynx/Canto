import Foundation
import Hako
import NetworkExtension

struct HakoCommandHello: Decodable, Equatable {
    let schemaVersion: Int32
    let minSchemaVersion: Int32
    let coreVersion: String
    let capabilities: [String]

    init(
        schemaVersion: Int32,
        minSchemaVersion: Int32,
        coreVersion: String,
        capabilities: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.minSchemaVersion = minSchemaVersion
        self.coreVersion = coreVersion
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, minSchemaVersion, coreVersion, capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int32.self, forKey: .schemaVersion)
        minSchemaVersion = try container.decode(Int32.self, forKey: .minSchemaVersion)
        coreVersion = try container.decode(String.self, forKey: .coreVersion)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func validate(
        localMin: Int32 = HakoCommandSchemaMinVersion,
        localCurrent: Int32 = HakoCommandSchemaVersion
    ) throws {
        guard minSchemaVersion > 0, schemaVersion >= minSchemaVersion else {
            throw HakoCommandCompatibilityError.invalidPeerRange(
                minimum: minSchemaVersion,
                current: schemaVersion
            )
        }
        guard schemaVersion >= localMin, minSchemaVersion <= localCurrent else {
            throw HakoCommandCompatibilityError.incompatible(
                localMinimum: localMin,
                localCurrent: localCurrent,
                peerMinimum: minSchemaVersion,
                peerCurrent: schemaVersion
            )
        }
    }
}

enum HakoCommandCapability {
    static let stunV1 = "stun-v1"
    static let forceGCV1 = "force-gc-v1"
}

enum HakoCommandCompatibilityError: LocalizedError, Equatable {
    case invalidPeerRange(minimum: Int32, current: Int32)
    case incompatible(localMinimum: Int32, localCurrent: Int32, peerMinimum: Int32, peerCurrent: Int32)
     
     
     
    case transportNotReady
    case transportNoReply
    case malformedHello(String)

    var errorDescription: String? {
        switch self {
        case let .invalidPeerRange(minimum, current):
            return "Extension returned an invalid command schema range \(minimum)...\(current)."
        case let .incompatible(localMinimum, localCurrent, peerMinimum, peerCurrent):
            return "App command schema \(localMinimum)...\(localCurrent) is incompatible with Extension \(peerMinimum)...\(peerCurrent). Reinstall or update Hako."
        case .transportNotReady:
            return "The tunnel is not ready to receive commands yet."
        case .transportNoReply:
            return "The tunnel extension did not reply to the command session."
        case let .malformedHello(reply):
            return "The tunnel extension replied with an unreadable hello: \(reply)"
        }
    }
}

struct HakoPhysicalPathEvent: Decodable, Equatable {
    let sequence: UInt64
    let unixTimeMilliseconds: Int64
    let interfaceName: String
    let interfaceType: String?
    let interfaceIndex: Int
    let satisfied: Bool
    let expensive: Bool
    let constrained: Bool
    let supportsIPv4: Bool
    let supportsIPv6: Bool
}

struct HakoOOMEvidence: Decodable, Equatable {
    let schemaVersion: Int
    let recordedAtUnix: Int64
    let pressureLevel: String
    let processIdentifier: Int
    let possibleSystemKill: Bool
    let physicalMemoryBytes: Int64
     
     
     
    let softMemoryLimit: Int64?
    let gcPercent: Int
    let coreState: String
    let coreStartTimeUnix: Int64
    let inboundCount: Int32
    let outboundCount: Int32
    let connectionCount: Int32
    let goroutineCount: Int
    let heapAllocBytes: UInt64
    let heapInuseBytes: UInt64
    let stackInuseBytes: UInt64
    let numGC: UInt32
     
     
     
    let reloadPhase: String?

     
     
     
     
     
     
    var interpretation: String {
        if pressureLevel == "reload" {
            let phase = reloadPhase.map { " (phase: \($0))" } ?? ""
            return "The previous Extension ended while applying a reload\(phase); "
                + "the reload built a second configuration beside the running one and iOS likely enforced the memory ceiling."
        }
        return "Critical memory pressure was recorded before the previous Extension ended; iOS may have terminated it."
    }
}

struct HakoRuntimeDiagnostics: Decodable, Equatable {
    let processIdentifier: Int32
    let startTimeUnix: Int64
    let goroutines: Int
    let inboundCount: Int32
    let outboundCount: Int32
    let connectionCount: Int32
    let running: Bool
    let dnsMainTransportTypes: [String]
    let dnsFallbackTransportTypes: [String]
    let dnsDefaultTransportTypes: [String]
    let dnsProxyTransportTypes: [String]
    let dnsDirectTransportTypes: [String]
    let dnsPolicyTransportTypes: [String]
    let outboundEndpointKinds: [String: String]
    let tunStrictRouteRequested: Bool
    let appleIPv4IncludedRouteCount: Int
    let appleIPv4ExcludedRouteCount: Int
    let appleIPv6IncludedRouteCount: Int
    let appleIPv6ExcludedRouteCount: Int
    let appleMTU: Int
     
     
     
    let extensionMemoryFootprintBytes: Int64?
    let lowMemoryBuild: Bool?
     
     
     
    let memoryThresholdState: String?
    let memoryThresholdTriggerCount: Int?
    let memoryThresholdPredictedCount: Int?
    let memoryThresholdShedCount: Int?
    let memoryThresholdShedEnabled: Bool?
    let applePhysicalInterfaceName: String
    let applePhysicalInterfaceType: String
    let applePhysicalInterfaceIndex: Int
    let applePhysicalPathSatisfied: Bool
    let applePhysicalPathExpensive: Bool
    let applePhysicalPathConstrained: Bool
    let applePhysicalPathSupportsIPv4: Bool
    let applePhysicalPathSupportsIPv6: Bool
    let applePhysicalPathUpdateCount: UInt64
    let applePhysicalPathHistory: [HakoPhysicalPathEvent]
    let appleProviderSleepCount: UInt64
    let appleProviderWakeCount: UInt64
    let physicalPathUpdatesReceived: UInt64
    let physicalPathUpdatesApplied: UInt64
    let physicalPathIdentityChanges: UInt64
    let physicalPathConnectionResets: UInt64
    let physicalPathSupportsIPv4: Bool
    let physicalPathSupportsIPv6: Bool
    let nat64SynthesisAttempts: UInt64
    let nat64SynthesisApplied: UInt64
    let nat64SynthesisFailures: UInt64
    let pauseCount: UInt64
    let wakeCount: UInt64
     
     
    let softMemoryLimit: Int64?
    let gcPercent: Int
    let logMaxLines: Int
    let physicalMemoryBytes: Int64
    let availableMemoryBytes: Int64
    let goRuntimeResidentBytes: UInt64
    let nonGoPhysicalEstimateBytes: Int64
    let goHeapAllocBytes: UInt64
    let goHeapInuseBytes: UInt64
    let goStackInuseBytes: UInt64
    let goGCCount: UInt32
    let goGCPauseTotalNanoseconds: UInt64
    let goMaxProcs: Int
    let memoryPressureEventCount: UInt64
    let tcpConnectionAdmissionLimit: Int64
    let tcpConnectionAdmissionActive: Int64
    let tcpConnectionAdmissionRejectedTotal: UInt64
    let processCPUTimeNanoseconds: Int64
    let packetFlowPacketsToCore: UInt64
    let packetFlowPacketsToSystem: UInt64
    let packetFlowDroppedToCore: UInt64
    let packetFlowDroppedToSystem: UInt64
    let packetFlowPendingPackets: Int
    let packetFlowPendingBytes: Int
    let packetFlowPeakPendingPackets: Int
    let packetFlowPeakPendingBytes: Int
    let packetFlowQueueLatencySamples: UInt64
    let packetFlowAverageQueueLatencyNanoseconds: UInt64
    let packetFlowMaxQueueLatencyNanoseconds: UInt64
    let packetFlowSystemWriteCalls: UInt64
    let packetFlowMaxSystemWriteBatch: Int
    let packetFlowConfiguredMaxDrainBatch: Int
    let packetFlowCoreToSystemFlushNanoseconds: UInt64
     
     
     
     
     
    let corePacketIngressReadCalls: UInt64?
    let corePacketIngressReadWouldBlock: UInt64?
    let corePacketIngressReadPackets: UInt64?
    let corePacketIngressReadBytes: UInt64?
    let corePacketIngressReadErrors: UInt64?
    let corePacketIngressDispatchPackets: UInt64?
    let corePacketIngressDispatchBytes: UInt64?
    let corePacketProcessorQueueDepth: UInt64?
    let corePacketProcessorQueuePeak: UInt64?
    let corePacketEgressWriteCalls: UInt64?
    let corePacketEgressWritePackets: UInt64?
    let corePacketEgressWriteBytes: UInt64?
    let corePacketEgressWriteErrors: UInt64?

    private enum CodingKeys: String, CodingKey {
        case processIdentifier, startTimeUnix, goroutines, inboundCount, outboundCount, connectionCount, running
        case dnsMainTransportTypes, dnsFallbackTransportTypes, dnsDefaultTransportTypes
        case dnsProxyTransportTypes, dnsDirectTransportTypes, dnsPolicyTransportTypes, outboundEndpointKinds
        case tunStrictRouteRequested, appleIPv4IncludedRouteCount, appleIPv4ExcludedRouteCount
        case appleIPv6IncludedRouteCount, appleIPv6ExcludedRouteCount, appleMTU
        case extensionMemoryFootprintBytes, lowMemoryBuild
        case memoryThresholdState, memoryThresholdTriggerCount
        case memoryThresholdPredictedCount, memoryThresholdShedCount
        case memoryThresholdShedEnabled
        case applePhysicalInterfaceName, applePhysicalInterfaceType, applePhysicalInterfaceIndex, applePhysicalPathSatisfied
        case applePhysicalPathExpensive, applePhysicalPathConstrained
        case applePhysicalPathSupportsIPv4, applePhysicalPathSupportsIPv6
        case applePhysicalPathUpdateCount, applePhysicalPathHistory
        case appleProviderSleepCount, appleProviderWakeCount
        case physicalPathUpdatesReceived, physicalPathUpdatesApplied
        case physicalPathIdentityChanges, physicalPathConnectionResets
        case physicalPathSupportsIPv4, physicalPathSupportsIPv6
        case nat64SynthesisAttempts, nat64SynthesisApplied, nat64SynthesisFailures
        case pauseCount, wakeCount
        case softMemoryLimit, gcPercent, logMaxLines
        case physicalMemoryBytes, availableMemoryBytes, goRuntimeResidentBytes, nonGoPhysicalEstimateBytes
        case goHeapAllocBytes, goHeapInuseBytes, goStackInuseBytes
        case goGCCount, goGCPauseTotalNanoseconds, goMaxProcs, memoryPressureEventCount
        case tcpConnectionAdmissionLimit, tcpConnectionAdmissionActive
        case tcpConnectionAdmissionRejectedTotal
        case processCPUTimeNanoseconds
        case packetFlowPacketsToCore, packetFlowPacketsToSystem, packetFlowDroppedToCore, packetFlowDroppedToSystem
        case packetFlowPendingPackets, packetFlowPendingBytes, packetFlowPeakPendingPackets, packetFlowPeakPendingBytes
        case packetFlowQueueLatencySamples, packetFlowAverageQueueLatencyNanoseconds, packetFlowMaxQueueLatencyNanoseconds
        case packetFlowSystemWriteCalls, packetFlowMaxSystemWriteBatch
        case packetFlowConfiguredMaxDrainBatch, packetFlowCoreToSystemFlushNanoseconds
        case corePacketIngressReadCalls, corePacketIngressReadWouldBlock
        case corePacketIngressReadPackets, corePacketIngressReadBytes, corePacketIngressReadErrors
        case corePacketIngressDispatchPackets, corePacketIngressDispatchBytes
        case corePacketProcessorQueueDepth, corePacketProcessorQueuePeak
        case corePacketEgressWriteCalls, corePacketEgressWritePackets
        case corePacketEgressWriteBytes, corePacketEgressWriteErrors
    }

    init(
        processIdentifier: Int32,
        startTimeUnix: Int64,
        goroutines: Int,
        inboundCount: Int32,
        outboundCount: Int32,
        connectionCount: Int32,
        running: Bool,
        dnsMainTransportTypes: [String] = [],
        dnsFallbackTransportTypes: [String] = [],
        dnsDefaultTransportTypes: [String] = [],
        dnsProxyTransportTypes: [String] = [],
        dnsDirectTransportTypes: [String] = [],
        dnsPolicyTransportTypes: [String] = [],
        outboundEndpointKinds: [String: String] = [:],
        tunStrictRouteRequested: Bool,
        appleIPv4IncludedRouteCount: Int,
        appleIPv4ExcludedRouteCount: Int,
        appleIPv6IncludedRouteCount: Int,
        appleIPv6ExcludedRouteCount: Int,
        appleMTU: Int,
        extensionMemoryFootprintBytes: Int64? = nil,
        lowMemoryBuild: Bool? = nil,
        memoryThresholdState: String? = nil,
        memoryThresholdTriggerCount: Int? = nil,
        memoryThresholdPredictedCount: Int? = nil,
        memoryThresholdShedCount: Int? = nil,
        memoryThresholdShedEnabled: Bool? = nil,
        applePhysicalInterfaceName: String = "",
        applePhysicalInterfaceType: String = "",
        applePhysicalInterfaceIndex: Int = 0,
        applePhysicalPathSatisfied: Bool = false,
        applePhysicalPathExpensive: Bool = false,
        applePhysicalPathConstrained: Bool = false,
        applePhysicalPathSupportsIPv4: Bool = false,
        applePhysicalPathSupportsIPv6: Bool = false,
        applePhysicalPathUpdateCount: UInt64 = 0,
        applePhysicalPathHistory: [HakoPhysicalPathEvent] = [],
        appleProviderSleepCount: UInt64 = 0,
        appleProviderWakeCount: UInt64 = 0,
        physicalPathUpdatesReceived: UInt64 = 0,
        physicalPathUpdatesApplied: UInt64 = 0,
        physicalPathIdentityChanges: UInt64 = 0,
        physicalPathConnectionResets: UInt64 = 0,
        physicalPathSupportsIPv4: Bool = false,
        physicalPathSupportsIPv6: Bool = false,
        nat64SynthesisAttempts: UInt64 = 0,
        nat64SynthesisApplied: UInt64 = 0,
        nat64SynthesisFailures: UInt64 = 0,
        pauseCount: UInt64 = 0,
        wakeCount: UInt64 = 0,
        softMemoryLimit: Int64? = nil,
        gcPercent: Int = 0,
        logMaxLines: Int = 0,
        physicalMemoryBytes: Int64 = -1,
        availableMemoryBytes: Int64 = -1,
        goRuntimeResidentBytes: UInt64 = 0,
        nonGoPhysicalEstimateBytes: Int64 = -1,
        goHeapAllocBytes: UInt64 = 0,
        goHeapInuseBytes: UInt64 = 0,
        goStackInuseBytes: UInt64 = 0,
        goGCCount: UInt32 = 0,
        goGCPauseTotalNanoseconds: UInt64 = 0,
        goMaxProcs: Int = 0,
        memoryPressureEventCount: UInt64 = 0,
        tcpConnectionAdmissionLimit: Int64 = 0,
        tcpConnectionAdmissionActive: Int64 = 0,
        tcpConnectionAdmissionRejectedTotal: UInt64 = 0,
        processCPUTimeNanoseconds: Int64 = -1,
        packetFlowPacketsToCore: UInt64 = 0,
        packetFlowPacketsToSystem: UInt64 = 0,
        packetFlowDroppedToCore: UInt64 = 0,
        packetFlowDroppedToSystem: UInt64 = 0,
        packetFlowPendingPackets: Int = 0,
        packetFlowPendingBytes: Int = 0,
        packetFlowPeakPendingPackets: Int = 0,
        packetFlowPeakPendingBytes: Int = 0,
        packetFlowQueueLatencySamples: UInt64 = 0,
        packetFlowAverageQueueLatencyNanoseconds: UInt64 = 0,
        packetFlowMaxQueueLatencyNanoseconds: UInt64 = 0,
        packetFlowSystemWriteCalls: UInt64 = 0,
        packetFlowMaxSystemWriteBatch: Int = 0,
        packetFlowConfiguredMaxDrainBatch: Int = 0,
        packetFlowCoreToSystemFlushNanoseconds: UInt64 = 0,
        corePacketIngressReadCalls: UInt64? = nil,
        corePacketIngressReadWouldBlock: UInt64? = nil,
        corePacketIngressReadPackets: UInt64? = nil,
        corePacketIngressReadBytes: UInt64? = nil,
        corePacketIngressReadErrors: UInt64? = nil,
        corePacketIngressDispatchPackets: UInt64? = nil,
        corePacketIngressDispatchBytes: UInt64? = nil,
        corePacketProcessorQueueDepth: UInt64? = nil,
        corePacketProcessorQueuePeak: UInt64? = nil,
        corePacketEgressWriteCalls: UInt64? = nil,
        corePacketEgressWritePackets: UInt64? = nil,
        corePacketEgressWriteBytes: UInt64? = nil,
        corePacketEgressWriteErrors: UInt64? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.startTimeUnix = startTimeUnix
        self.goroutines = goroutines
        self.inboundCount = inboundCount
        self.outboundCount = outboundCount
        self.connectionCount = connectionCount
        self.running = running
        self.dnsMainTransportTypes = dnsMainTransportTypes
        self.dnsFallbackTransportTypes = dnsFallbackTransportTypes
        self.dnsDefaultTransportTypes = dnsDefaultTransportTypes
        self.dnsProxyTransportTypes = dnsProxyTransportTypes
        self.dnsDirectTransportTypes = dnsDirectTransportTypes
        self.dnsPolicyTransportTypes = dnsPolicyTransportTypes
        self.outboundEndpointKinds = outboundEndpointKinds
        self.tunStrictRouteRequested = tunStrictRouteRequested
        self.appleIPv4IncludedRouteCount = appleIPv4IncludedRouteCount
        self.appleIPv4ExcludedRouteCount = appleIPv4ExcludedRouteCount
        self.appleIPv6IncludedRouteCount = appleIPv6IncludedRouteCount
        self.appleIPv6ExcludedRouteCount = appleIPv6ExcludedRouteCount
        self.appleMTU = appleMTU
        self.extensionMemoryFootprintBytes = extensionMemoryFootprintBytes
        self.lowMemoryBuild = lowMemoryBuild
        self.memoryThresholdState = memoryThresholdState
        self.memoryThresholdTriggerCount = memoryThresholdTriggerCount
        self.memoryThresholdPredictedCount = memoryThresholdPredictedCount
        self.memoryThresholdShedCount = memoryThresholdShedCount
        self.memoryThresholdShedEnabled = memoryThresholdShedEnabled
        self.applePhysicalInterfaceName = applePhysicalInterfaceName
        self.applePhysicalInterfaceType = applePhysicalInterfaceType
        self.applePhysicalInterfaceIndex = applePhysicalInterfaceIndex
        self.applePhysicalPathSatisfied = applePhysicalPathSatisfied
        self.applePhysicalPathExpensive = applePhysicalPathExpensive
        self.applePhysicalPathConstrained = applePhysicalPathConstrained
        self.applePhysicalPathSupportsIPv4 = applePhysicalPathSupportsIPv4
        self.applePhysicalPathSupportsIPv6 = applePhysicalPathSupportsIPv6
        self.applePhysicalPathUpdateCount = applePhysicalPathUpdateCount
        self.applePhysicalPathHistory = applePhysicalPathHistory
        self.appleProviderSleepCount = appleProviderSleepCount
        self.appleProviderWakeCount = appleProviderWakeCount
        self.physicalPathUpdatesReceived = physicalPathUpdatesReceived
        self.physicalPathUpdatesApplied = physicalPathUpdatesApplied
        self.physicalPathIdentityChanges = physicalPathIdentityChanges
        self.physicalPathConnectionResets = physicalPathConnectionResets
        self.physicalPathSupportsIPv4 = physicalPathSupportsIPv4
        self.physicalPathSupportsIPv6 = physicalPathSupportsIPv6
        self.nat64SynthesisAttempts = nat64SynthesisAttempts
        self.nat64SynthesisApplied = nat64SynthesisApplied
        self.nat64SynthesisFailures = nat64SynthesisFailures
        self.pauseCount = pauseCount
        self.wakeCount = wakeCount
        self.softMemoryLimit = softMemoryLimit
        self.gcPercent = gcPercent
        self.logMaxLines = logMaxLines
        self.physicalMemoryBytes = physicalMemoryBytes
        self.availableMemoryBytes = availableMemoryBytes
        self.goRuntimeResidentBytes = goRuntimeResidentBytes
        self.nonGoPhysicalEstimateBytes = nonGoPhysicalEstimateBytes
        self.goHeapAllocBytes = goHeapAllocBytes
        self.goHeapInuseBytes = goHeapInuseBytes
        self.goStackInuseBytes = goStackInuseBytes
        self.goGCCount = goGCCount
        self.goGCPauseTotalNanoseconds = goGCPauseTotalNanoseconds
        self.goMaxProcs = goMaxProcs
        self.memoryPressureEventCount = memoryPressureEventCount
        self.tcpConnectionAdmissionLimit = tcpConnectionAdmissionLimit
        self.tcpConnectionAdmissionActive = tcpConnectionAdmissionActive
        self.tcpConnectionAdmissionRejectedTotal = tcpConnectionAdmissionRejectedTotal
        self.processCPUTimeNanoseconds = processCPUTimeNanoseconds
        self.packetFlowPacketsToCore = packetFlowPacketsToCore
        self.packetFlowPacketsToSystem = packetFlowPacketsToSystem
        self.packetFlowDroppedToCore = packetFlowDroppedToCore
        self.packetFlowDroppedToSystem = packetFlowDroppedToSystem
        self.packetFlowPendingPackets = packetFlowPendingPackets
        self.packetFlowPendingBytes = packetFlowPendingBytes
        self.packetFlowPeakPendingPackets = packetFlowPeakPendingPackets
        self.packetFlowPeakPendingBytes = packetFlowPeakPendingBytes
        self.packetFlowQueueLatencySamples = packetFlowQueueLatencySamples
        self.packetFlowAverageQueueLatencyNanoseconds = packetFlowAverageQueueLatencyNanoseconds
        self.packetFlowMaxQueueLatencyNanoseconds = packetFlowMaxQueueLatencyNanoseconds
        self.packetFlowSystemWriteCalls = packetFlowSystemWriteCalls
        self.packetFlowMaxSystemWriteBatch = packetFlowMaxSystemWriteBatch
        self.packetFlowConfiguredMaxDrainBatch = packetFlowConfiguredMaxDrainBatch
        self.packetFlowCoreToSystemFlushNanoseconds = packetFlowCoreToSystemFlushNanoseconds
        self.corePacketIngressReadCalls = corePacketIngressReadCalls
        self.corePacketIngressReadWouldBlock = corePacketIngressReadWouldBlock
        self.corePacketIngressReadPackets = corePacketIngressReadPackets
        self.corePacketIngressReadBytes = corePacketIngressReadBytes
        self.corePacketIngressReadErrors = corePacketIngressReadErrors
        self.corePacketIngressDispatchPackets = corePacketIngressDispatchPackets
        self.corePacketIngressDispatchBytes = corePacketIngressDispatchBytes
        self.corePacketProcessorQueueDepth = corePacketProcessorQueueDepth
        self.corePacketProcessorQueuePeak = corePacketProcessorQueuePeak
        self.corePacketEgressWriteCalls = corePacketEgressWriteCalls
        self.corePacketEgressWritePackets = corePacketEgressWritePackets
        self.corePacketEgressWriteBytes = corePacketEgressWriteBytes
        self.corePacketEgressWriteErrors = corePacketEgressWriteErrors
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        processIdentifier = try values.decodeIfPresent(Int32.self, forKey: .processIdentifier) ?? 0
        startTimeUnix = try values.decode(Int64.self, forKey: .startTimeUnix)
        goroutines = try values.decode(Int.self, forKey: .goroutines)
        inboundCount = try values.decode(Int32.self, forKey: .inboundCount)
        outboundCount = try values.decode(Int32.self, forKey: .outboundCount)
        connectionCount = try values.decode(Int32.self, forKey: .connectionCount)
        running = try values.decode(Bool.self, forKey: .running)
        dnsMainTransportTypes = try values.decodeIfPresent([String].self, forKey: .dnsMainTransportTypes) ?? []
        dnsFallbackTransportTypes = try values.decodeIfPresent([String].self, forKey: .dnsFallbackTransportTypes) ?? []
        dnsDefaultTransportTypes = try values.decodeIfPresent([String].self, forKey: .dnsDefaultTransportTypes) ?? []
        dnsProxyTransportTypes = try values.decodeIfPresent([String].self, forKey: .dnsProxyTransportTypes) ?? []
        dnsDirectTransportTypes = try values.decodeIfPresent([String].self, forKey: .dnsDirectTransportTypes) ?? []
        dnsPolicyTransportTypes = try values.decodeIfPresent([String].self, forKey: .dnsPolicyTransportTypes) ?? []
        outboundEndpointKinds = try values.decodeIfPresent([String: String].self, forKey: .outboundEndpointKinds) ?? [:]
        tunStrictRouteRequested = try values.decodeIfPresent(Bool.self, forKey: .tunStrictRouteRequested) ?? false
        appleIPv4IncludedRouteCount = try values.decodeIfPresent(Int.self, forKey: .appleIPv4IncludedRouteCount) ?? 0
        appleIPv4ExcludedRouteCount = try values.decodeIfPresent(Int.self, forKey: .appleIPv4ExcludedRouteCount) ?? 0
        appleIPv6IncludedRouteCount = try values.decodeIfPresent(Int.self, forKey: .appleIPv6IncludedRouteCount) ?? 0
        appleIPv6ExcludedRouteCount = try values.decodeIfPresent(Int.self, forKey: .appleIPv6ExcludedRouteCount) ?? 0
        appleMTU = try values.decodeIfPresent(Int.self, forKey: .appleMTU) ?? 0
        extensionMemoryFootprintBytes = try values.decodeIfPresent(
            Int64.self, forKey: .extensionMemoryFootprintBytes)
        lowMemoryBuild = try values.decodeIfPresent(Bool.self, forKey: .lowMemoryBuild)
        memoryThresholdState = try values.decodeIfPresent(
            String.self, forKey: .memoryThresholdState)
        memoryThresholdTriggerCount = try values.decodeIfPresent(
            Int.self, forKey: .memoryThresholdTriggerCount)
        memoryThresholdPredictedCount = try values.decodeIfPresent(
            Int.self, forKey: .memoryThresholdPredictedCount)
        memoryThresholdShedCount = try values.decodeIfPresent(
            Int.self, forKey: .memoryThresholdShedCount)
        memoryThresholdShedEnabled = try values.decodeIfPresent(
            Bool.self, forKey: .memoryThresholdShedEnabled)
        applePhysicalInterfaceName = try values.decodeIfPresent(String.self, forKey: .applePhysicalInterfaceName) ?? ""
        applePhysicalInterfaceType = try values.decodeIfPresent(String.self, forKey: .applePhysicalInterfaceType) ?? ""
        applePhysicalInterfaceIndex = try values.decodeIfPresent(Int.self, forKey: .applePhysicalInterfaceIndex) ?? 0
        applePhysicalPathSatisfied = try values.decodeIfPresent(Bool.self, forKey: .applePhysicalPathSatisfied) ?? false
        applePhysicalPathExpensive = try values.decodeIfPresent(Bool.self, forKey: .applePhysicalPathExpensive) ?? false
        applePhysicalPathConstrained = try values.decodeIfPresent(Bool.self, forKey: .applePhysicalPathConstrained) ?? false
        applePhysicalPathSupportsIPv4 = try values.decodeIfPresent(Bool.self, forKey: .applePhysicalPathSupportsIPv4) ?? false
        applePhysicalPathSupportsIPv6 = try values.decodeIfPresent(Bool.self, forKey: .applePhysicalPathSupportsIPv6) ?? false
        applePhysicalPathUpdateCount = try values.decodeIfPresent(UInt64.self, forKey: .applePhysicalPathUpdateCount) ?? 0
        applePhysicalPathHistory = try values.decodeIfPresent([HakoPhysicalPathEvent].self, forKey: .applePhysicalPathHistory) ?? []
        appleProviderSleepCount = try values.decodeIfPresent(UInt64.self, forKey: .appleProviderSleepCount) ?? 0
        appleProviderWakeCount = try values.decodeIfPresent(UInt64.self, forKey: .appleProviderWakeCount) ?? 0
        physicalPathUpdatesReceived = try values.decodeIfPresent(UInt64.self, forKey: .physicalPathUpdatesReceived) ?? 0
        physicalPathUpdatesApplied = try values.decodeIfPresent(UInt64.self, forKey: .physicalPathUpdatesApplied) ?? 0
        physicalPathIdentityChanges = try values.decodeIfPresent(UInt64.self, forKey: .physicalPathIdentityChanges) ?? 0
        physicalPathConnectionResets = try values.decodeIfPresent(UInt64.self, forKey: .physicalPathConnectionResets) ?? 0
        physicalPathSupportsIPv4 = try values.decodeIfPresent(Bool.self, forKey: .physicalPathSupportsIPv4) ?? false
        physicalPathSupportsIPv6 = try values.decodeIfPresent(Bool.self, forKey: .physicalPathSupportsIPv6) ?? false
        nat64SynthesisAttempts = try values.decodeIfPresent(UInt64.self, forKey: .nat64SynthesisAttempts) ?? 0
        nat64SynthesisApplied = try values.decodeIfPresent(UInt64.self, forKey: .nat64SynthesisApplied) ?? 0
        nat64SynthesisFailures = try values.decodeIfPresent(UInt64.self, forKey: .nat64SynthesisFailures) ?? 0
        pauseCount = try values.decodeIfPresent(UInt64.self, forKey: .pauseCount) ?? 0
        wakeCount = try values.decodeIfPresent(UInt64.self, forKey: .wakeCount) ?? 0
        softMemoryLimit = try values.decodeIfPresent(Int64.self, forKey: .softMemoryLimit)
        gcPercent = try values.decodeIfPresent(Int.self, forKey: .gcPercent) ?? 0
        logMaxLines = try values.decodeIfPresent(Int.self, forKey: .logMaxLines) ?? 0
        physicalMemoryBytes = try values.decodeIfPresent(Int64.self, forKey: .physicalMemoryBytes) ?? -1
        availableMemoryBytes = try values.decodeIfPresent(Int64.self, forKey: .availableMemoryBytes) ?? -1
        goRuntimeResidentBytes = try values.decodeIfPresent(UInt64.self, forKey: .goRuntimeResidentBytes) ?? 0
        nonGoPhysicalEstimateBytes = try values.decodeIfPresent(Int64.self, forKey: .nonGoPhysicalEstimateBytes) ?? -1
        goHeapAllocBytes = try values.decodeIfPresent(UInt64.self, forKey: .goHeapAllocBytes) ?? 0
        goHeapInuseBytes = try values.decodeIfPresent(UInt64.self, forKey: .goHeapInuseBytes) ?? 0
        goStackInuseBytes = try values.decodeIfPresent(UInt64.self, forKey: .goStackInuseBytes) ?? 0
        goGCCount = try values.decodeIfPresent(UInt32.self, forKey: .goGCCount) ?? 0
        goGCPauseTotalNanoseconds = try values.decodeIfPresent(UInt64.self, forKey: .goGCPauseTotalNanoseconds) ?? 0
        goMaxProcs = try values.decodeIfPresent(Int.self, forKey: .goMaxProcs) ?? 0
        memoryPressureEventCount = try values.decodeIfPresent(UInt64.self, forKey: .memoryPressureEventCount) ?? 0
        tcpConnectionAdmissionLimit = try values.decodeIfPresent(
            Int64.self,
            forKey: .tcpConnectionAdmissionLimit
        ) ?? 0
        tcpConnectionAdmissionActive = try values.decodeIfPresent(
            Int64.self,
            forKey: .tcpConnectionAdmissionActive
        ) ?? 0
        tcpConnectionAdmissionRejectedTotal = try values.decodeIfPresent(
            UInt64.self,
            forKey: .tcpConnectionAdmissionRejectedTotal
        ) ?? 0
        processCPUTimeNanoseconds = try values.decodeIfPresent(Int64.self, forKey: .processCPUTimeNanoseconds) ?? -1
        packetFlowPacketsToCore = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowPacketsToCore) ?? 0
        packetFlowPacketsToSystem = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowPacketsToSystem) ?? 0
        packetFlowDroppedToCore = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowDroppedToCore) ?? 0
        packetFlowDroppedToSystem = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowDroppedToSystem) ?? 0
        packetFlowPendingPackets = try values.decodeIfPresent(Int.self, forKey: .packetFlowPendingPackets) ?? 0
        packetFlowPendingBytes = try values.decodeIfPresent(Int.self, forKey: .packetFlowPendingBytes) ?? 0
        packetFlowPeakPendingPackets = try values.decodeIfPresent(Int.self, forKey: .packetFlowPeakPendingPackets) ?? 0
        packetFlowPeakPendingBytes = try values.decodeIfPresent(Int.self, forKey: .packetFlowPeakPendingBytes) ?? 0
        packetFlowQueueLatencySamples = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowQueueLatencySamples) ?? 0
        packetFlowAverageQueueLatencyNanoseconds = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowAverageQueueLatencyNanoseconds) ?? 0
        packetFlowMaxQueueLatencyNanoseconds = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowMaxQueueLatencyNanoseconds) ?? 0
        packetFlowSystemWriteCalls = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowSystemWriteCalls) ?? 0
        packetFlowMaxSystemWriteBatch = try values.decodeIfPresent(Int.self, forKey: .packetFlowMaxSystemWriteBatch) ?? 0
        packetFlowConfiguredMaxDrainBatch = try values.decodeIfPresent(Int.self, forKey: .packetFlowConfiguredMaxDrainBatch) ?? 0
        packetFlowCoreToSystemFlushNanoseconds = try values.decodeIfPresent(UInt64.self, forKey: .packetFlowCoreToSystemFlushNanoseconds) ?? 0
         
         
        corePacketIngressReadCalls = try values.decodeIfPresent(UInt64.self, forKey: .corePacketIngressReadCalls)
        corePacketIngressReadWouldBlock = try values.decodeIfPresent(UInt64.self, forKey: .corePacketIngressReadWouldBlock)
        corePacketIngressReadPackets = try values.decodeIfPresent(UInt64.self, forKey: .corePacketIngressReadPackets)
        corePacketIngressReadBytes = try values.decodeIfPresent(UInt64.self, forKey: .corePacketIngressReadBytes)
        corePacketIngressReadErrors = try values.decodeIfPresent(UInt64.self, forKey: .corePacketIngressReadErrors)
        corePacketIngressDispatchPackets = try values.decodeIfPresent(UInt64.self, forKey: .corePacketIngressDispatchPackets)
        corePacketIngressDispatchBytes = try values.decodeIfPresent(UInt64.self, forKey: .corePacketIngressDispatchBytes)
        corePacketProcessorQueueDepth = try values.decodeIfPresent(UInt64.self, forKey: .corePacketProcessorQueueDepth)
        corePacketProcessorQueuePeak = try values.decodeIfPresent(UInt64.self, forKey: .corePacketProcessorQueuePeak)
        corePacketEgressWriteCalls = try values.decodeIfPresent(UInt64.self, forKey: .corePacketEgressWriteCalls)
        corePacketEgressWritePackets = try values.decodeIfPresent(UInt64.self, forKey: .corePacketEgressWritePackets)
        corePacketEgressWriteBytes = try values.decodeIfPresent(UInt64.self, forKey: .corePacketEgressWriteBytes)
        corePacketEgressWriteErrors = try values.decodeIfPresent(UInt64.self, forKey: .corePacketEgressWriteErrors)
    }
}

struct HakoProviderRestartEvidence: Decodable, Equatable {
    let requested: Int
    let completed: Int
    let processIdentifiers: [Int32]
    let goroutineCounts: [Int]
    let error: String
}

 
 
 
private actor HakoIPCChannel {
    static let shared = HakoIPCChannel()
    static let timeoutNanoseconds: UInt64 = 15_000_000_000

    private enum Outcome {
        case reply(Data)
        case emptyReply
        case failure(NSError)
        case timeout
    }

    private struct Pending {
        let id: UUID
        let session: NETunnelProviderSession
        let data: Data
        let timeoutNanoseconds: UInt64
        let began: DispatchTime
        let continuation: CheckedContinuation<Data?, Never>
    }

    private var queue: [Pending] = []
    private var current: Pending?
    private var timeoutTask: Task<Void, Never>?
    // 诊断日志抑制：同样的失败 2s 内只记一条，被压掉的条数补在下一行。
    // 没有它，「每秒重试」会把日志预算写穿（app 流只有 128KB）。
    private var lastOutcomeLog: (text: String, at: Date)?
    private var suppressedOutcomeLogs = 0

    func send(
        session: NETunnelProviderSession,
        data: Data,
        timeoutNanoseconds: UInt64 = HakoIPCChannel.timeoutNanoseconds
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.append(Pending(
                id: UUID(),
                session: session,
                data: data,
                timeoutNanoseconds: timeoutNanoseconds,
                began: DispatchTime.now(),
                continuation: continuation
            ))
            startNextIfNeeded()
        }
    }

    /// `HakoClient.send` 在 session 非 active 时会静默返回 nil——2026-10-21 的
    /// 日志证明这条路径会让「压根没发」看起来和「扩展不回包」一模一样。
    func noteSkipped(status: String) {
        logOutcome("skipped session-not-active", status: status)
    }

    private func startNextIfNeeded() {
        guard current == nil, !queue.isEmpty else { return }
        let pending = queue.removeFirst()
        current = pending
        let status = HakoClient.statusName(pending.session.status)
        do {
            try pending.session.sendProviderMessage(pending.data) { [weak self] reply in
                Task {
                    await self?.finish(
                        id: pending.id,
                        outcome: reply.map(Outcome.reply) ?? .emptyReply,
                        status: status
                    )
                }
            }
        } catch {
            // 2026-10-21：底层错误必须可见——sendProviderMessage 抛出的
            // NSError（domain/code）此前被吞成 nil reply，导致「扩展不回包」
            // 无法与「发送即失败」区分。
            let nsError = error as NSError
            NSLog(
                "hako-ipc sendProviderMessage failed domain=%@ code=%d msg=%@",
                nsError.domain, nsError.code,
                nsError.localizedDescription
            )
            logOutcome(
                "send failed domain=\(nsError.domain) code=\(nsError.code) msg=\(nsError.localizedDescription)",
                status: status
            )
            finish(id: pending.id, outcome: .failure(nsError), status: status)
            return
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: pending.timeoutNanoseconds)
            await self?.finish(id: pending.id, outcome: .timeout, status: status)
        }
    }

    private func finish(id: UUID, outcome: Outcome, status: String) {
        guard let pending = current, pending.id == id else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        current = nil
        let elapsed = Self.milliseconds(since: pending.began)
        let reply: Data?
        switch outcome {
        case let .reply(data):
            reply = data
        case .emptyReply:
            logOutcome("reply empty elapsed=\(elapsed)ms", status: status)
            reply = nil
        case .failure:
            // domain/code 与耗时已在 startNextIfNeeded 的 catch 里记过。
            reply = nil
        case .timeout:
            logOutcome("timeout elapsed=\(elapsed)ms", status: status)
            reply = nil
        }
        pending.continuation.resume(returning: reply)
        startNextIfNeeded()
    }

    /// 强制写入（不受「日志录制」开关影响）：这条通道的诊断信息是排查
    /// 「VPN 已连但显示未连接」的唯一线索，用户关掉日志录制也必须留下。
    private func logOutcome(_ text: String, status: String) {
        let now = Date()
        if let last = lastOutcomeLog, last.text == text, now.timeIntervalSince(last.at) < 2 {
            suppressedOutcomeLogs += 1
            return
        }
        let suffix = suppressedOutcomeLogs > 0 ? " suppressed=\(suppressedOutcomeLogs)" : ""
        suppressedOutcomeLogs = 0
        lastOutcomeLog = (text, now)
        HakoLogStore.shared.append(
            "ipc \(text) status=\(status)\(suffix)",
            stream: .app,
            level: .warning,
            force: true
        )
    }

    private static func milliseconds(since began: DispatchTime) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= began.uptimeNanoseconds else { return 0 }
        return Int((now - began.uptimeNanoseconds) / 1_000_000)
    }
}


 
struct HakoClient {
    let session: NETunnelProviderSession

    var isVPNActive: Bool {
        session.status == .connected || session.status == .reasserting
    }

    func send(
        _ payload: [String: Any],
        timeoutNanoseconds: UInt64 = HakoIPCChannel.timeoutNanoseconds
    ) async -> Data? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        guard isVPNActive else {
            // 这条分支以前是静默的；它和「扩展不回包」在日志里无法区分。
            await HakoIPCChannel.shared.noteSkipped(status: Self.statusName(session.status))
            return nil
        }
        return await HakoIPCChannel.shared.send(
            session: session,
            data: data,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    static func statusName(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    func hello() async throws -> HakoCommandHello {
        guard await waitUntilActive(upToNanoseconds: 3_000_000_000) else {
            HakoLogStore.shared.append(
                "control hello not-ready status=\(Self.statusName(session.status))",
                stream: .app, level: .warning, force: true
            )
            throw HakoCommandCompatibilityError.transportNotReady
        }
        HakoLogStore.shared.append(
            "control hello begin status=\(Self.statusName(session.status))",
            stream: .app, level: .info, force: true
        )
        // 2026-10-21：session 变 connected 不等于扩展已跑完 startTunnel
        //（配置解析 + TUN + 控制面 1-2s）。此前一次 15s 硬等会整段落空，
        // 现在改为 2s 短超时 + 5 次重试（累计约 12s），覆盖扩展启动窗口。
        var lastReply: Data?
        for attempt in 0..<5 {
            if let data = await send(
                ["cmd": "hello"],
                timeoutNanoseconds: 2_000_000_000
            ) {
                lastReply = data
                break
            }
            if attempt < 4 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        guard let data = lastReply else {
            // 兜底：扩展启动时会把 hello 写进 App Group 并每 60s 刷新。
            // 消息通道被系统拒绝时（全能签重签环境），直接拿文件里的
            // schema 去连 clash.sock——连接/流量/节点/日志就能恢复显示。
            if let fallback = Self.appGroupHello() {
                HakoLogStore.shared.append(
                    "control hello ok source=app-group-file age=\(Int(fallback.age))s core=\(fallback.hello.coreVersion)",
                    stream: .app, level: .warning, force: true
                )
                return fallback.hello
            }
            HakoLogStore.shared.append(
                "control hello failed status=\(Self.statusName(session.status)) fallback=unavailable",
                stream: .app, level: .warning, force: true
            )
            throw HakoCommandCompatibilityError.transportNoReply
        }
        do {
            let hello = try JSONDecoder().decode(HakoCommandHello.self, from: data)
            try hello.validate()
            HakoLogStore.shared.append(
                "control hello ok peer=\(hello.minSchemaVersion)...\(hello.schemaVersion) core=\(hello.coreVersion)",
                stream: .app, level: .info
            )
            return hello
        } catch let error as HakoCommandCompatibilityError {
            throw error
        } catch {
            let raw = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            throw HakoCommandCompatibilityError.malformedHello(raw)
        }
    }

    /// 隧道刚变 connected 的头几十毫秒内，session 状态与扩展消息通道尚未就绪，
    /// 立即发 hello 会直接拿到 nil（旧代码把它误报成 schema 0...0）。
    /// 这里按需轮询等待，最多 3 秒。
    private func waitUntilActive(upToNanoseconds limit: UInt64) async -> Bool {
        if isVPNActive { return true }
        let step: UInt64 = 100_000_000
        var waited: UInt64 = 0
        while waited < limit {
            try? await Task.sleep(nanoseconds: step)
            waited += step
            if isVPNActive { return true }
        }
        return isVPNActive
    }

    /// 读扩展写下的 hello 兜底文件。心跳 60s 一次，超过 180s 视为扩展已不在
    /// （避免 VPN 重启后拿到上一次进程的陈旧 schema）。
    private static func appGroupHello(now: Date = Date()) -> (hello: HakoCommandHello, age: TimeInterval)? {
        guard let container = HakoAppIdentifiers.resolvedAppGroupContainer
            ?? HakoAppIdentifiers.appGroupContainer,
            let payload = HakoIpcHelloFile.read(in: container)
        else { return nil }
        let age = now.timeIntervalSince1970 - Double(payload.writtenAtUnix)
        guard age >= -5, age <= HakoIpcHelloFile.maximumAgeSeconds else { return nil }
        let hello = HakoCommandHello(
            schemaVersion: payload.schemaVersion,
            minSchemaVersion: payload.minSchemaVersion,
            coreVersion: payload.coreVersion,
            capabilities: payload.capabilities
        )
        do {
            try hello.validate()
        } catch {
            return nil
        }
        return (hello, age)
    }

    func runtimeDiagnostics() async throws -> HakoRuntimeDiagnostics {
        guard let data = await send(["cmd": "runtimeDiagnostics"]) else {
            throw URLError(.cannotConnectToHost)
        }
        return try JSONDecoder().decode(HakoRuntimeDiagnostics.self, from: data)
    }

    /// provider message 被系统拒绝时的诊断读取：先落请求标记（扩展 1s 轮询），
    /// 再等扩展把同一份 JSON 写进共享容器。连接列表的运行时身份确认依赖它。
    static func runtimeDiagnosticsFromAppGroup() async throws -> HakoRuntimeDiagnostics {
        guard let container = HakoAppIdentifiers.resolvedAppGroupContainer
            ?? HakoAppIdentifiers.appGroupContainer
        else { throw URLError(.cannotConnectToHost) }
        HakoIpcDiagnosticsFile.request(in: container)
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            if Task.isCancelled { throw CancellationError() }
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let sample = HakoIpcDiagnosticsFile.read(in: container),
               sample.age <= HakoIpcDiagnosticsFile.maximumAgeSeconds {
                do {
                    let diagnostics = try JSONDecoder().decode(HakoRuntimeDiagnostics.self, from: sample.data)
                    noteFileDiagnostics("ipc diagnostics ok source=app-group-file age=\(Int(sample.age))s")
                    return diagnostics
                } catch {
                    throw URLError(.cannotParseResponse)
                }
            }
        }
        noteFileDiagnostics("ipc diagnostics failed source=app-group-file age=timeout")
        throw URLError(.timedOut)
    }

    private static let diagnosticsFileLogLock = NSLock()
    private static var lastDiagnosticsFileLog: (message: String, at: Date)?

    /// 文件通道是否生效对排查很关键，但每次诊断请求都记会刷屏：同一内容 60s 一条。
    private static func noteFileDiagnostics(_ message: String) {
        diagnosticsFileLogLock.lock()
        let now = Date()
        let shouldLog = ControlConnectFailureLogGate.shouldLog(
            message, after: lastDiagnosticsFileLog, now: now
        )
        if shouldLog { lastDiagnosticsFileLog = (message, now) }
        diagnosticsFileLogLock.unlock()
        guard shouldLog else { return }
        HakoLogStore.shared.append(message, stream: .app, level: .warning, force: true)
    }

    func forceGarbageCollection() async throws {
        guard let data = await send(["cmd": "forceGC"]) else {
            throw URLError(.cannotConnectToHost)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        if let message = object["error"] as? String {
            throw NSError(
                domain: "HakoClient",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        guard object["ok"] as? Bool == true else {
            throw CocoaError(.coderReadCorrupt)
        }
    }

     
     
     
     
    func consumeGoCrashReport() async -> String? {
        guard let data = await send(["cmd": "consumeGoCrashReport"]) else {
            return nil
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["error"] != nil {
            return nil
        }
        let report = String(decoding: data, as: UTF8.self)
        return report.isEmpty ? nil : report
    }

    func consumeOOMEvidence() async throws -> HakoOOMEvidence {
        guard let data = await send(["cmd": "consumeOOMEvidence"]) else {
            throw NSError(
                domain: "HakoClient",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "OOM evidence unavailable"]
            )
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String {
            throw NSError(
                domain: "HakoClient",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return try JSONDecoder().decode(HakoOOMEvidence.self, from: data)
    }

    func restartProviderInProcessForTesting(cycles: Int) async {
        _ = await send(
            ["cmd": "restartProviderInProcess", "cycles": cycles],
            timeoutNanoseconds: 60_000_000_000
        )
    }

    func status() async -> [String: String] {
        guard let d = await send(["cmd": "status"]),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: String]
        else { return [:] }
        return obj
    }

    func traffic() async -> [String: Int64] {
        guard let d = await send(["cmd": "traffic"]),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Int64]
        else { return [:] }
        return obj
    }

    func proxies() async -> Data? { await send(["cmd": "proxies"]) }
    func connections() async -> Data? { await send(["cmd": "connections"]) }

    func logs() async -> [String] {
        guard let d = await send(["cmd": "logs"]),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [String] else { return [] }
        return arr
    }

    @discardableResult
    func setMode(_ mode: String) async -> Data? { await send(["cmd": "setMode", "mode": mode]) }
    @discardableResult
    func select(group: String, name: String) async -> Data? {
        await send(["cmd": "select", "group": group, "name": name])
    }

     
    func urltest(name: String, url: String = "") async -> Int {
        guard let d = await send(["cmd": "urltest", "name": name, "url": url]),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let delay = obj["delay"] as? Int
        else { return -1 }
        return delay
    }
}
