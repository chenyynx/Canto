import Foundation
import HakoClientUI
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

 
 
 
struct ConnectionsView: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @ObservedObject var model: ConnectionsModel
    @ObservedObject var command: ClashCommandClient
    var autoStart = true
     
    var query = ""
     
    var isShown = true

    var body: some View {
        HakoClientUI.HakoConnectionsView(
            snapshot: HakoActivityIOSAdapter.snapshot(
                model: model,
                isConnected: command.isConnected,
                tunnelIsUp: command.tunnelIsUp,
                channelFailed: command.channelAttachFailed
            ),
            actions: AppleClientActions(capability: .activity) {
                action in
                guard case .activity(let activity) = action else {
                    return
                }
                switch activity {
                case .refresh:
                     
                     
                     
                    if command.isConnected { await model.refresh() }
                    else { command.reconnectIfNeeded() }
                 
                case .closeConnection(let id):
                    await model.close(id)
                case .closeAllConnections:
                    await model.closeAll()
                case .copyText(let value):
#if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
#else
                    UIPasteboard.general.string = value
#endif
                case .clearRequests:
                    await model.clearRequestHistory()
                case .clearLogs, .exportLogs, .setLogRecording, .setLogRetention,
                     .setLogSeverityFilter, .setLogLevelDirective, .openLogSettings:
                    break
                }
            },
            presentationClass:
                horizontalSizeClass == .regular
                    ? .regularTouch
                    : .compactTouch,
            palette: HakoActivityIOSAdapter.palette,
            query: query,
            isShown: isShown
        ) { symbol in
            HakoSymbolImage(symbol: symbol)
        }
        .onAppear {
            guard autoStart else { return }
            model.start(
                commandConnected: command.isConnected
            )
        }
        .onDisappear {
            guard autoStart else { return }
            model.stop()
        }
        .onChange(of: command.isConnected) { connected in
            guard autoStart else { return }
            model.sync(connected)
        }
    }
}

@MainActor
enum HakoActivityIOSAdapter {
    static let palette = HakoClientUI.HakoProductPalette.clashProduct

     
     
     
     
     
     
    static var tunnelIsUp = false

    static func snapshot(
        model: ConnectionsModel? = nil,
        isConnected: Bool,
        tunnelIsUp: Bool = false,
         
         
         
        channelFailed: Bool = false,
        logLines: [String] = [],
        exposesLogActions: Bool = false,
        isRecordingLogs: Bool? = nil,
        logRetentionOptions: [HakoLogRetentionOption] = [],
        logRetention: String? = nil,
        logRetentionSummary: String? = nil,
        logSeverityFilter: [String] = [],
        activeProfileLogLevel: String? = nil,
        logLevelDirective: String? = nil
    ) -> AppleClientSnapshot {
        let connections =
            model?.activityConnections ?? []
        let requests = model?.requestLog.map { entry in
            HakoActivityRequestSnapshot(
                connection: entry.connection,
                firstSeen: entry.firstSeen,
                lastSeen: entry.lastSeen,
                closedAt: entry.closedAt,
                observationID: entry.id
            )
        } ?? []
        let phase = phase(
            model: model,
            isConnected: isConnected,
            tunnelIsUp: tunnelIsUp,
            channelFailed: channelFailed
        )

        return AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase:
                    phase == .ready
                    ? .connected
                    : phase == .loading
                        ? .preparing
                        : phase == .disconnected
                            ? .disconnected
                            : .unavailable
            ),
            activity: HakoActivitySnapshot(
                phase: phase,
                activeConnectionCount: connections.count,
                recentLogCount: logLines.count,
                detailAvailability: .full,
                errorDescription:
                    model?.error.isEmpty == false
                        || (channelFailed && !isConnected && (tunnelIsUp || Self.tunnelIsUp))
                        ? "The connections stream is unavailable."
                        : nil,
                connections: connections,
                requests: requests,
                 
                 
                 
                 
                 
                 
                 
                 
                 
                logLines: logLines,
                closingConnectionIDs:
                    model?.closing ?? [],
                isClosingAll: model?.closingAll ?? false,
                canManageConnections:
                    model?.isStreaming == true
                        && (
                            isConnected
                                || model?.connected == true
                        ),
                canClearLogs: exposesLogActions,
                canExportLogs: exposesLogActions,
            isRecordingLogs: isRecordingLogs,
            logRetentionOptions: logRetentionOptions,
            logRetention: logRetention,
            logRetentionSummary: logRetentionSummary,
            logSeverityFilter: logSeverityFilter,
            activeProfileLogLevel: activeProfileLogLevel,
            logLevelDirective: logLevelDirective
            ),
            capabilities: AppleClientCapabilities([
                .activity: .available,
            ])
        )
    }

    private static func phase(
        model: ConnectionsModel?,
        isConnected: Bool,
        tunnelIsUp: Bool,
        channelFailed: Bool
    ) -> HakoActivityPhase {
        if model?.loading == true {
            return .loading
        }
        if let error = model?.error,
           !error.isEmpty,
           model?.connected != true
        {
            return .failed
        }
        if isConnected || model?.connected == true {
            return .ready
        }
         
         
         
         
        if tunnelIsUp || Self.tunnelIsUp {
            if model?.activityConnections.isEmpty == false { return .ready }
            return channelFailed ? .failed : .loading
        }
        return .disconnected
    }
}


