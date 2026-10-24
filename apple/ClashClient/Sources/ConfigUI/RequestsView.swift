import ClashClientUI
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

 
 
struct RequestsView: View {
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @ObservedObject var model: ConnectionsModel
     
     
    var command: ClashCommandClient?
     
    var query = ""
     
    var isShown = true

    var body: some View {
        ClashClientUI.ClashRequestsView(
            snapshot: ClashActivityIOSAdapter.snapshot(
                model: model,
                 
                 
                isConnected: model.connected && model.isStreaming,
                 
                 
                 
                tunnelIsUp: model.tunnelIsUp,
                channelFailed: model.channelFailed
            ),
            actions: AppleClientActions(capability: .activity) {
                action in
                guard case .activity(let activity) = action else {
                    return
                }
                switch activity {
                case .copyText(let value):
                    ClashClipboard.copy(value, feedback: feedback, operation: "requests.copy")
                case .refresh:
                    if let command, !command.isConnected { command.reconnectIfNeeded() }
                    else { await model.refresh() }
                 
                case .closeConnection(let id):
                    if let reason = await model.close(id) {
                        feedback?.show(.error(title: .copy("Couldn’t Close the Connection"), message: .verbatim(reason),
                                              accessibilityIdentifier: "feedback.connections.close"),
                                       operation: "connections.close")
                    }
                case .closeAllConnections:
                    if let reason = await model.closeAll() {
                        feedback?.show(.error(title: .copy("Couldn’t Close the Connections"), message: .verbatim(reason),
                                              accessibilityIdentifier: "feedback.connections.close"),
                                       operation: "connections.close")
                    }
                case .clearRequests:
                    model.clearRequestHistory()
                case .clearLogs, .exportLogs, .setLogRecording, .setLogRetention,
                     .setLogSeverityFilter, .setLogLevelDirective, .openLogSettings:
                    break
                }
            },
            presentationClass:
                horizontalSizeClass == .regular
                    ? .regularTouch
                    : .compactTouch,
            palette: ClashActivityIOSAdapter.palette,
            query: query,
            isShown: isShown
        ) { symbol in
            ClashSymbolImage(symbol: symbol)
        }
    }
}


