import Foundation
import ClashClientKit

public enum ClashProfileSourceKind:
    String,
    Codable,
    Equatable,
    Sendable
{
    case remote
    case file
    case clipboard
}

public struct ClashProfileSubscriptionSnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let uploadBytes: Int64
    public let downloadBytes: Int64
    public let totalBytes: Int64
    public let expiration: Date?

    public init(
        uploadBytes: Int64,
        downloadBytes: Int64,
        totalBytes: Int64,
        expiration: Date? = nil
    ) {
        self.uploadBytes = max(0, uploadBytes)
        self.downloadBytes = max(0, downloadBytes)
        self.totalBytes = max(0, totalBytes)
        self.expiration = expiration
    }

    public var usedBytes: Int64 {
        let (sum, overflow) = uploadBytes.addingReportingOverflow(
            downloadBytes
        )
        return overflow ? Int64.max : sum
    }

    public var usageFraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

 
 
 
public struct ClashProfileFeatureAvailabilitySnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let canRename: Bool
    public let canSync: Bool
    public let canConfigureSubscription: Bool
    public let canCopySubscriptionLink: Bool
    public let canDuplicate: Bool
    public let canExport: Bool
    public let canOpenRuntimePreview: Bool
    public let canRestoreLastKnownGood: Bool

    public init(
        canRename: Bool = true,
        canSync: Bool = true,
        canConfigureSubscription: Bool = true,
        canCopySubscriptionLink: Bool = true,
        canDuplicate: Bool = true,
        canExport: Bool = true,
        canOpenRuntimePreview: Bool = true,
        canRestoreLastKnownGood: Bool = false
    ) {
        self.canRename = canRename
        self.canSync = canSync
        self.canConfigureSubscription = canConfigureSubscription
        self.canCopySubscriptionLink = canCopySubscriptionLink
        self.canDuplicate = canDuplicate
        self.canExport = canExport
        self.canOpenRuntimePreview = canOpenRuntimePreview
        self.canRestoreLastKnownGood = canRestoreLastKnownGood
    }

    public static let full = ClashProfileFeatureAvailabilitySnapshot()
}

public extension ClashProfileSnapshot {
     
     
     
    var sourceUpdatesState: ConfigurationUpdateFollowing? {
        configurationUpdateFollowing ?? followsConfigurationSourceUpdates.map { $0 ? .following : .paused }
    }

     
     
     
     
    static func sourceUpdatesNote(_ state: ConfigurationUpdateFollowing, canPickLink: Bool = false) -> ClashDisplayText? {
        switch state {
        case .following, .paused: return nil
        case .ownCopy:
            return .copy("Changed here, so it runs its own copy and the link’s updates don’t reach it. Turn this on to go back to the link’s content.")
        case .customizedRules:
            return .copy("Its rules were changed here, so the link’s rule updates don’t reach it. Turn this on to go back to the link’s rules.")
        case .copyWithoutOrigin:
             
             
            return canPickLink
                ? .copy("Changed here, so it runs its own copy. Turn this on to choose a link to follow.")
                : .copy("Changed here, so it runs its own copy and no longer follows its link. To follow the link again, add it again.")
        }
    }

     
     
    static func offersSourceUpdatesSwitch(_ state: ConfigurationUpdateFollowing, canPickLink: Bool) -> Bool {
        state != .copyWithoutOrigin || canPickLink
    }

     
    var linksToPick: [ClashProfileLinkChoice] { configurationLinksToRejoin ?? [] }

     
    static func turningOnReplacesChanges(_ state: ConfigurationUpdateFollowing?) -> Bool {
        state == .ownCopy || state == .customizedRules
    }
}

 
public struct ClashProfileLinkChoice: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct ClashProfileSnapshot:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: Profile.ID
    public let label: String
    public let source: ClashProfileSourceKind
    public var sourceSummary: ClashDisplayText
    public var subscription: ClashProfileSubscriptionSnapshot?
    public var lastUpdatedAt: Date?
    public let autoUpdate: Bool
    public let updateIntervalHours: Int
    public let isCurrent: Bool
    public let isBusy: Bool
    public let canEditSource: Bool
     
     
    public let canOpenConfigurationPage: Bool?
    public let followsConfigurationSourceUpdates: Bool?
     
     
     
    public let configurationUpdateFollowing: ConfigurationUpdateFollowing?
     
     
    public let configurationLinksToRejoin: [ClashProfileLinkChoice]?
     
     
     
    public let overrideScriptName: String?
     
     
     
     
     
    public let customRulesCount: Int
    public let isComposed: Bool?
     
     
     
    public let canUseOriginalConfiguration: Bool
    public let configurationSourceNames: [String]?
    public let configurationRuleName: String?
    public let canDelete: Bool
    public let deleteSubtitle: ClashDisplayText
    public let runtimeSummary: ClashDisplayText
    public let requiresPlaintextExportConfirmation: Bool
    public let featureAvailability:
        ClashProfileFeatureAvailabilitySnapshot?
     
     
    public let heldBackUpdates: [ClashProfileHeldBackUpdate]
     
     
     
    public let badges: [ClashDisplayText]
     
     
    public let note: ClashDisplayText?

    public init(
        id: Profile.ID,
        label: String,
        source: ClashProfileSourceKind,
        sourceSummary: ClashDisplayText,
        subscription: ClashProfileSubscriptionSnapshot? = nil,
        lastUpdatedAt: Date? = nil,
        autoUpdate: Bool = false,
        updateIntervalHours: Int = 12,
        isCurrent: Bool = false,
        isBusy: Bool = false,
        canEditSource: Bool = false,
        canDelete: Bool = true,
        deleteSubtitle: ClashDisplayText = "Remove this profile from Clash",
        runtimeSummary: ClashDisplayText = "read-only",
        requiresPlaintextExportConfirmation: Bool = false,
        featureAvailability:
            ClashProfileFeatureAvailabilitySnapshot? = nil,
        heldBackUpdates: [ClashProfileHeldBackUpdate] = [],
        isComposed: Bool? = nil,
        canUseOriginalConfiguration: Bool = false,
        configurationSourceNames: [String]? = nil, configurationRuleName: String? = nil,
        followsConfigurationSourceUpdates: Bool? = nil,
        configurationUpdateFollowing: ConfigurationUpdateFollowing? = nil,
        configurationLinksToRejoin: [ClashProfileLinkChoice]? = nil,
        overrideScriptName: String? = nil,
        customRulesCount: Int = 0,
        badges: [ClashDisplayText] = [],
        note: ClashDisplayText? = nil,
        canOpenConfigurationPage: Bool? = nil
    ) {
        self.id = id
        self.canOpenConfigurationPage = canOpenConfigurationPage
        self.badges = badges
        self.note = note
        self.overrideScriptName = overrideScriptName
        self.customRulesCount = max(0, customRulesCount)
        self.followsConfigurationSourceUpdates = followsConfigurationSourceUpdates
        self.configurationUpdateFollowing = configurationUpdateFollowing
        self.configurationLinksToRejoin = configurationLinksToRejoin
        self.isComposed = isComposed
        self.canUseOriginalConfiguration = canUseOriginalConfiguration
        self.configurationSourceNames = configurationSourceNames
        self.configurationRuleName = configurationRuleName
        self.heldBackUpdates = heldBackUpdates
        self.label = String(label.prefix(256))
        self.source = source
        self.sourceSummary = sourceSummary.bounded(to: 256)
        self.subscription = subscription
        self.lastUpdatedAt = lastUpdatedAt
        self.autoUpdate = autoUpdate
        self.updateIntervalHours = min(max(updateIntervalHours, 1), 168)
        self.isCurrent = isCurrent
        self.isBusy = isBusy
        self.canEditSource = canEditSource
        self.canDelete = canDelete
        self.deleteSubtitle = deleteSubtitle.bounded(to: 256)
        self.runtimeSummary = runtimeSummary.bounded(to: 256)
        self.requiresPlaintextExportConfirmation =
            requiresPlaintextExportConfirmation
        self.featureAvailability = featureAvailability
    }

     
     
    public static func customRulesValue(count: Int, locale: Locale) -> ClashDisplayText {
        count <= 0 ? .copy("None") : .verbatim(ClashCopy.format("%d rules", locale: locale, count))
    }

    public var canRename: Bool {
        featureAvailability?.canRename ?? true
    }

    public var canSync: Bool {
        featureAvailability?.canSync ?? true
    }

     
     
     
     
    public var isTakenOverByScript: Bool { overrideScriptName != nil }
    public static let takenOverByScript: ClashDisplayText = .copy("Taken over by the override script")

    public var canConfigureSubscription: Bool {
        featureAvailability?.canConfigureSubscription ?? true
    }

    public var canCopySubscriptionLink: Bool {
        featureAvailability?.canCopySubscriptionLink ?? true
    }

    public var canDuplicate: Bool {
        featureAvailability?.canDuplicate ?? true
    }

    public var canExport: Bool {
        featureAvailability?.canExport ?? true
    }

    public var canOpenRuntimePreview: Bool {
        featureAvailability?.canOpenRuntimePreview ?? true
    }

    public var canRestoreLastKnownGood: Bool {
        featureAvailability?.canRestoreLastKnownGood ?? false
    }
}

public struct ClashProfilesFailureSnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let message: ClashDisplayText
    public let canRetry: Bool

    public init(message: ClashDisplayText, canRetry: Bool = false) {
        self.message = message
        self.canRetry = canRetry
    }
}

public enum ClashProfileBatchUpdateState:
    String,
    Codable,
    Equatable,
    Sendable
{
    case updated
    case unchanged
    case failed

    public var title: String {
        switch self {
        case .updated:
            "Updated"
        case .unchanged:
            "Up to Date"
        case .failed:
            "Failed"
        }
    }
}

public struct ClashProfileBatchItemSnapshot:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: Profile.ID
    public let label: String
    public let state: ClashProfileBatchUpdateState
    public let message: String
    public let diagnosticCode: String?

    public init(
        id: Profile.ID,
        label: String,
        state: ClashProfileBatchUpdateState,
        message: String,
        diagnosticCode: String? = nil
    ) {
        self.id = id
        self.label = String(label.prefix(256))
        self.state = state
        self.message = String(message.prefix(512))
        self.diagnosticCode = diagnosticCode.map {
            String($0.prefix(128))
        }
    }
}

public struct ClashProfileBatchReportSnapshot:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let title: String
    public let expectedCount: Int
    public let items: [ClashProfileBatchItemSnapshot]
    public let wasCancelled: Bool
    public let isRunning: Bool

    public init(
        id: UUID,
        title: String,
        expectedCount: Int,
        items: [ClashProfileBatchItemSnapshot],
        wasCancelled: Bool = false,
        isRunning: Bool = false
    ) {
        self.id = id
        self.title = String(title.prefix(160))
        self.expectedCount = max(0, expectedCount)
        self.items = Array(items.prefix(512))
        self.wasCancelled = wasCancelled
        self.isRunning = isRunning
    }

    public var updatedCount: Int {
        items.filter { $0.state == .updated }.count
    }

    public var unchangedCount: Int {
        items.filter { $0.state == .unchanged }.count
    }

    public var failedCount: Int {
        items.filter { $0.state == .failed }.count
    }

     
     
    public var needsAttention: Bool {
        failedCount > 0 || wasCancelled
    }

     
     
    public var settledKey: String {
        "\(id.uuidString):\(isRunning)"
    }

     
     
     
     
     
     
    public var summaryParts: [ClashDisplayText] {
        var parts: [ClashDisplayText] = [
            .format("%@ updated", [String(updatedCount)]),
            .format("%@ unchanged", [String(unchangedCount)]),
        ]
        if failedCount > 0 {
            parts.append(.format("%@ failed", [String(failedCount)]))
        }
        if wasCancelled {
            parts.append("cancelled")
        }
        return parts
    }
}

public struct ClashProfilesFeatureAvailabilitySnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let canCreateEmpty: Bool
    public let canImport: Bool
    public let canBackup: Bool
    public let canReorder: Bool
    public let canSyncAll: Bool

    public init(
        canCreateEmpty: Bool = true,
        canImport: Bool = true,
        canBackup: Bool = true,
        canReorder: Bool = true,
        canSyncAll: Bool = true
    ) {
        self.canCreateEmpty = canCreateEmpty
        self.canImport = canImport
        self.canBackup = canBackup
        self.canReorder = canReorder
        self.canSyncAll = canSyncAll
    }

    public static let full = ClashProfilesFeatureAvailabilitySnapshot()
}

 
 
 
public struct ClashModulesEntrySnapshot: Codable, Equatable, Sendable {
    public let value: ClashDisplayText

    public init(value: ClashDisplayText) {
        self.value = value
    }

     
     
     
    public init(decryptionOn: Bool, certificateReady: Bool, enabledModules: Int) {
        if decryptionOn, !certificateReady {
            self.init(value: "Certificate Needed")
        } else if enabledModules > 0 {
            self.init(value: .format(enabledModules == 1 ? "%@ Module On" : "%@ Modules On", ["\(enabledModules)"]))
        } else {
            self.init(value: "Off")
        }
    }
}

public struct ClashProfilesSnapshot: Codable, Equatable, Sendable {
    public let profiles: [ClashProfileSnapshot]
    public let failure: ClashProfilesFailureSnapshot?
    public let statusMessage: ClashDisplayText
    public let batchReport: ClashProfileBatchReportSnapshot?
    public let featureAvailability:
        ClashProfilesFeatureAvailabilitySnapshot?
     
     
     
    public let libraryHasFetchableSource: Bool
    public let modules: ClashModulesEntrySnapshot?

    public init(
        profiles: [ClashProfileSnapshot] = [],
        failure: ClashProfilesFailureSnapshot? = nil,
        statusMessage: ClashDisplayText = .copy(""),
        batchReport: ClashProfileBatchReportSnapshot? = nil,
        featureAvailability:
            ClashProfilesFeatureAvailabilitySnapshot? = nil,
        libraryHasFetchableSource: Bool = false,
        modules: ClashModulesEntrySnapshot? = nil
    ) {
        self.profiles = Array(profiles.prefix(1_024))
        self.failure = failure
        self.statusMessage = statusMessage.bounded(to: 512)
        self.batchReport = batchReport
        self.featureAvailability = featureAvailability
        self.libraryHasFetchableSource = libraryHasFetchableSource
        self.modules = modules
    }

    private enum CodingKeys: String, CodingKey {
        case profiles, failure, statusMessage, batchReport, featureAvailability, libraryHasFetchableSource
         
        case modules = "adBlock"
    }

     
     
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decode([ClashProfileSnapshot].self, forKey: .profiles)
        failure = try container.decodeIfPresent(ClashProfilesFailureSnapshot.self, forKey: .failure)
        statusMessage = try container.decode(ClashDisplayText.self, forKey: .statusMessage)
        batchReport = try container.decodeIfPresent(ClashProfileBatchReportSnapshot.self, forKey: .batchReport)
        featureAvailability = try container.decodeIfPresent(ClashProfilesFeatureAvailabilitySnapshot.self, forKey: .featureAvailability)
        libraryHasFetchableSource = try container.decodeIfPresent(Bool.self, forKey: .libraryHasFetchableSource) ?? false
        modules = try container.decodeIfPresent(ClashModulesEntrySnapshot.self, forKey: .modules)
    }

    public func profile(id: Profile.ID) -> ClashProfileSnapshot? {
        profiles.first { $0.id == id }
    }

    public var canCreateEmpty: Bool {
        featureAvailability?.canCreateEmpty ?? true
    }

    public var canImport: Bool {
        featureAvailability?.canImport ?? true
    }

    public var canBackup: Bool {
        featureAvailability?.canBackup ?? true
    }

    public var canReorder: Bool {
        featureAvailability?.canReorder ?? true
    }

    public var canSyncAll: Bool {
        featureAvailability?.canSyncAll ?? true
    }

    public static let empty = ClashProfilesSnapshot()
}


 
 
 
 
public struct ClashProfileHeldBackUpdate: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Change: String, Codable, Sendable { case changed, added, removed }
    public let keyPath: String
    public let change: Change
     
     
    public let newValue: String?
    public let appValue: String

    public var id: String { keyPath }
    public init(keyPath: String, change: Change, newValue: String?, appValue: String) {
        self.keyPath = keyPath
        self.change = change
        self.newValue = newValue
        self.appValue = appValue
    }
}
