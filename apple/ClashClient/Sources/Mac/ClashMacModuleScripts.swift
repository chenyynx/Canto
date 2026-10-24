import Combine
import Foundation

extension ModuleAppScriptRunner {
     
     
     
     
     
     
    static let shared: ModuleAppScriptRunner = ModuleAppScriptRunner(
        container: ClashAppIdentifiers.appGroupContainer
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("no-app-group", isDirectory: true),
        tunnelIsConnected: { ClashMacModuleScripts.tunnelIsConnected() },
        config: ModuleAppScriptCoreAccess.config(),
        dns: ModuleAppScriptCoreAccess.dns(),
        selectPolicy: ModuleAppScriptCoreAccess.selectPolicy()
    )
}

extension ClashMacScriptDriver.Runner {
     
     
     
    @MainActor
    static func of(_ runner: ModuleAppScriptRunner) -> Self {
        func found(_ entry: ClashMacScriptDriver.Entry, _ kind: ModuleAppScriptKind) -> ModuleAppScriptEntry? {
            runner.entries(kind).first { $0.id == entry.id }
        }
        return Self(
            cronEntries: { runner.entries(.cron).map(ClashMacModuleScripts.entry) },
            networkChangedEntries: { runner.entries(.networkChanged).map(ClashMacModuleScripts.entry) },
            nextFire: { entry, date in found(entry, .cron).flatMap { runner.nextFire(of: $0, after: date) } },
            run: { entry, trigger in
                let kind: ModuleAppScriptKind = trigger == .networkChanged ? .networkChanged : .cron
                 
                guard let script = found(entry, kind) else { return .ran }
                let result = await runner.run(script, trigger: ClashMacModuleScripts.trigger(trigger))
                return ClashMacModuleScripts.answer(result)
            }
        )
    }
}

 
 
 
 
 
 
 
@MainActor
enum ClashMacModuleScripts {
     
    static var tunnelIsConnected: @MainActor () -> Bool = { false }

    private static var driver: ClashMacScriptDriver?
    private static var changes: AnyCancellable?

    static var isStarted: Bool { driver != nil }

    static func start(tunnelIsConnected: @escaping @MainActor () -> Bool,
                      environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard driver == nil, environment["XCTestConfigurationFilePath"] == nil else { return }
        self.tunnelIsConnected = tunnelIsConnected
        Task { await ModuleScriptNotificationPermission.shared.start() }
        ModuleScriptNotificationPoster.askFirst = { done in
            Task { @MainActor in done(await ModuleScriptNotificationPermission.shared.mayShowNotification()) }
        }
        let runner = ModuleAppScriptRunner.shared
        let driver = ClashMacScriptDriver(runner: .of(runner), tunnelIsConnected: tunnelIsConnected)
        self.driver = driver
        Task { @MainActor in
            await runner.reload()
            driver.start()
             
             
            changes = runner.$entries.dropFirst().removeDuplicates().sink { _ in
                MainActor.assumeIsolated { driver.rearm() }
            }
        }
    }

    nonisolated static func entry(_ script: ModuleAppScriptEntry) -> ClashMacScriptDriver.Entry {
        ClashMacScriptDriver.Entry(id: script.id, name: script.name)
    }

    nonisolated static func trigger(_ trigger: ClashMacScriptDriver.Trigger) -> ModuleAppScriptTrigger {
        switch trigger {
        case .cron(let scheduled): return .cron(scheduled: scheduled)
        case .networkChanged: return .networkChanged
        }
    }

    nonisolated static func answer(_ result: ModuleAppScriptResult) -> ClashMacScriptDriver.Answer {
        result.outcome == .notRun(.busy) ? .busy : .ran
    }
}
