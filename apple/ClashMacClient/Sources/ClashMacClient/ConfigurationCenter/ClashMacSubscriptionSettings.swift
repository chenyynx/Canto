import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
public struct ClashMacSubscriptionSettingsState: Equatable, Sendable {
    public var url: String
    public var autoUpdate: Bool
    public var updateIntervalHours: Int
    public var canStripCredentials: Bool

    public init(url: String, autoUpdate: Bool, updateIntervalHours: Int, canStripCredentials: Bool) {
        self.url = url
        self.autoUpdate = autoUpdate
        self.updateIntervalHours = updateIntervalHours
        self.canStripCredentials = canStripCredentials
    }
}

 
 
public struct ClashMacSubscriptionSettingsActions {
    public var save: @MainActor (ClashMacSubscriptionSettingsState) async throws -> ClashMacSubscriptionSettingsState
    public var stripCredentials: @MainActor () async throws -> ClashMacSubscriptionSettingsState

    public init(
        save: @escaping @MainActor (ClashMacSubscriptionSettingsState) async throws -> ClashMacSubscriptionSettingsState,
        stripCredentials: @escaping @MainActor () async throws -> ClashMacSubscriptionSettingsState
    ) {
        self.save = save
        self.stripCredentials = stripCredentials
    }

    public static var unavailable: ClashMacSubscriptionSettingsActions {
        ClashMacSubscriptionSettingsActions(
            save: { _ in throw ConfigurationLibraryError.unreadable },
            stripCredentials: { throw ConfigurationLibraryError.unreadable }
        )
    }
}
