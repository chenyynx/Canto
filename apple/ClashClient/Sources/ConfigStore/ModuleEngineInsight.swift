#if os(iOS) || os(macOS)
import ClashClientKit
import Foundation

 
 
 
 
struct ModuleEngineInsight: Equatable {
    var notices: [AuthoredText] = []
     
    var pinnedHosts: [String] = []
     
     
    var leftOutModules: [ModuleEngineReport.OmittedModule] = []
     
    var blocked = 0
     
    var rewritten = 0
    var scriptsRun = 0
    var decryptedSessions = 0
    var rung: ModuleEngineReport.Rung = .normal

     
     
     
     
     
    static func read(_ report: ModuleEngineReport?, platform: ModuleCertificatePlatform = .current) -> ModuleEngineInsight {
        guard let report else { return ModuleEngineInsight() }
        var insight = ModuleEngineInsight()
        let counters = report.counters
        insight.blocked = counters.rejectsTotal + counters.dropsTotal
        insight.rewritten = counters.redirectsTotal + counters.headerRewritesTotal + counters.bodyRewritesTotal
        insight.scriptsRun = counters.scriptsRunTotal
        insight.decryptedSessions = counters.mitmSessionsTotal
        insight.pinnedHosts = report.pinnedHosts.filter(\.passedThrough).sorted { $0.lastAt > $1.lastAt }.map(\.host)
         
        guard [.starting, .running, .passThrough].contains(report.state) else { return insight }
        insight.rung = report.rung
        insight.leftOutModules = report.omittedModules
        if case .certificateUnreadable? = report.failure { insight.notices.append(Copy.certificateUnreadable) }
        switch report.rung {
        case .normal:
            break
        case .scriptsStopped:
            insight.notices.append(report.rungCause == .scriptsUnavailable ? Copy.scriptsUnavailable : Copy.scriptsPaused)
        case .bodiesStopped:
            insight.notices.append(Copy.bodiesPaused)
        case .engineStopped:
            insight.notices.append(platform == .mac ? Copy.decryptionPausedUntilReconnect
                                   : ModuleDegradeReason.stoppedForMemory.authoredText)
        }
         
         
        let grew = min(counters.rulesLeftOutTooLargeThisRun, counters.rulesLeftOutThisRun)
        if counters.rulesLeftOutThisRun > grew { insight.notices.append(Copy.rewritesStopped) }
        if grew > 0 { insight.notices.append(Copy.rewritesTooLarge) }
        if counters.rewriteOverBudget + counters.scriptOverBudget > 0 { insight.notices.append(Copy.tooManyRewrites) }
        insight.notices += report.omittedModules.map(Copy.leftOut)
        insight.notices += insight.pinnedHosts.map(Copy.pinned)
        return insight
    }

    static func load(_ locations: ModuleEngineLocations) -> ModuleEngineInsight {
        read(ModuleEngineReport.load(locations))
    }

     
     
     
    enum Copy {
        static let scriptsPaused: AuthoredText = .app("Rewrites and scripts are paused to keep your network steady; rules still work.")
        static let scriptsUnavailable: AuthoredText = .app("Scripts can't run on this device right now; rules still work.")
        static let bodiesPaused: AuthoredText = scriptsPaused
         
        static var certificateUnreadable: AuthoredText { ModuleDegradeReason.certificateUnusable.authoredText }
         
         
        static let decryptionPausedUntilReconnect: AuthoredText =
            .app("HTTPS Decryption is paused to keep your network steady; rules still work. It comes back when you reconnect.")
         
         
        static let rewritesStopped: AuthoredText =
            .app("Some rewrites took too long and were stopped; they come back when you reconnect.")
         
         
        static let rewritesTooLarge: AuthoredText =
            .app("Some rewrites made results too large and were stopped; they come back when you reconnect.")
         
        static let tooManyRewrites: AuthoredText = .app("Your modules have too many rewrites and scripts, so some were skipped.")

         
         
         
         
        static func leftOut(_ module: ModuleEngineReport.OmittedModule) -> AuthoredText {
            let name = module.name.trimmingCharacters(in: .whitespacesAndNewlines)
            switch module.reason {
            case .overBudget:
                return name.isEmpty ? .app("A module has too much in it, so it was skipped.") : moduleTooLarge(name)
            case .overSharedBudget:
                 
                return name.isEmpty ? .app("Too many modules are on, so one of them didn't take effect; turn some off to make room.")
                    : tooManyModulesOn(name)
            case .unreadable, .digestMismatch, .scriptMismatch:
                return name.isEmpty ? .app("A module couldn't be loaded this time, so it was skipped.") : moduleNotLoaded(name)
            }
        }

         
        static func moduleNotLoaded(_ name: String) -> AuthoredText {
            .app("The module “%@” couldn't be loaded this time, so it was skipped.", arguments: [name])
        }

         
        static func moduleTooLarge(_ name: String) -> AuthoredText {
            .app("The module “%@” has too much in it, so it was skipped.", arguments: [name])
        }

         
        static func tooManyModulesOn(_ name: String) -> AuthoredText {
            .app("Too many modules are on, so “%@” didn't take effect; turn some off to make room.", arguments: [name])
        }

         
         
         
        static func pinned(_ host: String) -> AuthoredText {
            .app("%@ isn't affected by modules.", arguments: [host])
        }

        static var every: [AuthoredText] {
            [scriptsPaused, scriptsUnavailable, bodiesPaused, certificateUnreadable, decryptionPausedUntilReconnect, rewritesStopped,
             rewritesTooLarge, tooManyRewrites, moduleNotLoaded("A"), moduleTooLarge("A"), tooManyModulesOn("A"),
             leftOut(.init(id: "a", name: "", reason: .unreadable, detail: "")),
             leftOut(.init(id: "a", name: "", reason: .overBudget, detail: "")),
             leftOut(.init(id: "a", name: "", reason: .overSharedBudget, detail: "")), pinned("a.example")]
        }
    }
}
#endif
