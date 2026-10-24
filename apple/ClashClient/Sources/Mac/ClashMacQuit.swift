import AppKit
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacQuit {
     
    enum Occasion: Equatable {
         
        case readerQuit
         
         
         
         
        case readerQuitLeavingTunnelRunning
         
         
         
        case relaunchForLanguageChange
         
         
         
         
         
         
         
        case systemEndingSession
    }

     
     
     
     
    static func quitReason(_ descriptor: NSAppleEventDescriptor?) -> OSType? {
        guard let descriptor else { return nil }
        let code = descriptor.enumCodeValue != 0
            ? descriptor.enumCodeValue
            : descriptor.typeCodeValue
        return code == 0 ? nil : code
    }

     
     
     
     
    private static let sessionEndingReasons: Set<OSType> = [
        OSType(kAELogOut), OSType(kAEReallyLogOut),
        OSType(kAERestart), OSType(kAEShutDown),
        OSType(kAEShowRestartDialog), OSType(kAEShowShutdownDialog),
    ]

     
     
     
    static func occasion(quitReason: OSType?, requested: Occasion) -> Occasion {
        guard case .readerQuit = requested,
              let quitReason,
              sessionEndingReasons.contains(quitReason) else { return requested }
        return .systemEndingSession
    }

     
     
     
     
     
     
     
     
     
     
     
    static func tunnelIsUp(status: String) -> Bool {
        ["connected", "connecting", "reasserting", "disconnecting"]
            .contains(status.lowercased())
    }

     
     
     
     
     
    static var nextTermination: Occasion = .readerQuit

    private let isTunnelUp: () -> Bool
    private let stop: () async -> Void
    private let allowTermination: () -> Void
    private let settle: () async -> Void
    private let settleAttempts: Int

     
     
    private(set) var teardown: Task<Void, Never>?

    init(
        isTunnelUp: @escaping () -> Bool,
        stop: @escaping () async -> Void,
        allowTermination: @escaping () -> Void,
         
         
         
         
         
         
         
         
        settle: @escaping () async -> Void = {
            try? await Task.sleep(nanoseconds: 25_000_000)
        },
        settleAttempts: Int = 160
    ) {
        self.isTunnelUp = isTunnelUp
        self.stop = stop
        self.allowTermination = allowTermination
        self.settle = settle
        self.settleAttempts = settleAttempts
    }

    func reply(for occasion: Occasion) -> NSApplication.TerminateReply {
        guard case .readerQuit = occasion else { return .terminateNow }
        guard isTunnelUp() else { return .terminateNow }
        teardown = Task { @MainActor [self] in
            await stop()
             
             
             
             
            var attempts = 0
            while isTunnelUp(), attempts < settleAttempts {
                attempts += 1
                await settle()
            }
             
             
            allowTermination()
        }
        return .terminateLater
    }
}


 
 
