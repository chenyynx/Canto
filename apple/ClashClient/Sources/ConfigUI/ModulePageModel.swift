#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import Foundation
#if canImport(UIKit)
import SafariServices
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

 
 
 
@MainActor
final class ModuleEntrySource: ObservableObject {
    @Published private(set) var entry: ClashModulesEntrySnapshot?

    func set(_ entry: ClashModulesEntrySnapshot?) {
        if self.entry != entry { self.entry = entry }
    }
}

 
 
 
 
@MainActor
final class ModuleAddRequest: ObservableObject {
    @Published private(set) var link: String?
    @Published private(set) var isPageOnScreen = false
    private var pagesOnScreen = 0

     
    func request(link: String) {
        self.link = link
    }

     
    func settle() {
        if link != nil { link = nil }
    }

    func pageAppeared() {
        pagesOnScreen += 1
        if !isPageOnScreen { isPageOnScreen = true }
    }

    func pageDisappeared() {
        pagesOnScreen = max(0, pagesOnScreen - 1)
        if isPageOnScreen, pagesOnScreen == 0 { isPageOnScreen = false }
    }
}

 
 
 
 
@MainActor
final class ModulePageModel: ObservableObject {
    struct Dependencies {
        var container: URL
        var modules: ModuleStore
        var readiness: ModuleEngineReadinessSource
        var platform: ModulePlatform = .current
        var isConnected: @MainActor () -> Bool = ModulePageModel.isConnectedHere
         
         
         
         
         
         
         
         
         
         
        var reconnect: (URL) async -> Void = { container in
            _ = await ModuleChangeTakers.shared.reconnect(in: container)
        }
        var open: (URL) -> Void = ModulePageModel.openInSystem
#if os(iOS)
         
         
         
        var profileServer: (_ handOut: ModuleCertificateHandOut, _ fetched: @escaping @Sendable () -> Void,
                            _ stopped: @escaping @Sendable (ModuleCertificateProfileServer.Stop) -> Void)
            -> ModuleCertificateProfileServer = { handOut, fetched, stopped in
                ModuleCertificateProfileServer(profile: handOut.profile, page: handOut.page, fetched: fetched, stopped: stopped)
            }
         
         
         
         
        var presentProfilePage: @MainActor (_ page: URL, _ closed: @escaping @MainActor () -> Void) -> Void =
            ModulePageModel.presentInApp
#endif
         
         
        var openCertificateFile: (URL) -> Void = { _ in }
         
         
         
        var installAndTrust: @Sendable (Data) -> ModuleCertificateInstallOutcome = { _ in
            .failed(.install, status: errSecUnimplemented)
        }
         
         
        var openKeychainAccess: () -> Void = {}
         
         
         
        var removeCertificate: @Sendable (Data) -> ModuleCertificateRemoval = { _ in .failed(status: errSecUnimplemented) }
         
         
        var isCertificateLeft: @Sendable (Data) -> Bool = { _ in false }
         
         
         
        var copy: @MainActor (String) -> Void = { ClashClipboard.copy($0, feedback: nil, operation: "modules.detail.copy") }
         
         
         
         
        var runPanelScript: @MainActor (_ module: String, _ script: String, _ byReader: Bool) async -> ModuleAppScriptResult? = { _, _, _ in nil }
        var now: () -> Date = Date.init

        var certificates: ModuleCertificateStore { readiness.certificates }

        static func production() -> Dependencies? {
            guard let container = ClashAppIdentifiers.appGroupContainer else { return nil }
            var dependencies = Dependencies(container: container, modules: ModuleStore.shared(container),
                                            readiness: ModuleEngineReadinessSource.shared(container))
#if os(macOS)
             
            dependencies.openCertificateFile = { ModuleKeychainAccess.open($0) }
            dependencies.installAndTrust = { ModuleKeychainAccess.installAndTrust($0) }
            dependencies.openKeychainAccess = { ModuleKeychainAccess.openApplication() }
            dependencies.removeCertificate = { ModuleKeychainAccess.remove($0) }
            dependencies.isCertificateLeft = { ModuleKeychainAccess.isInKeychain($0) }
#endif
            dependencies.runPanelScript = { module, script, byReader in
                let runner = ModuleAppScriptRunner.shared
                guard let entry = runner.entries(.generic).first(where: { $0.moduleID == module && $0.name == script }) else { return nil }
                return await runner.run(entry, trigger: .panel(byReader: byReader))
            }
            return dependencies
        }
    }

     
     
    @MainActor
    static func isConnectedHere() -> Bool {
#if os(macOS)
        isConnectedOnTheMac?() ?? false
#else
        ClashSystemActionDispatch.handoff.isVPNSnapshotActive
#endif
    }

#if os(macOS)
     
    static var isConnectedOnTheMac: (@MainActor () -> Bool)?
#endif

    static let shared = ModulePageModel(dependencies: .production())

    @Published private(set) var snapshot = ClashModulesSnapshot.off
    @Published private(set) var details: [String: ClashModuleDetailSnapshot] = [:]
    @Published private(set) var isAdding = false
    @Published var addRefusal: ClashDisplayText?
    let entrySource = ModuleEntrySource()
    let addRequest = ModuleAddRequest()
    var locale: Locale = AppPreferences.language().localeOverride ?? .current

    private let deps: Dependencies?
    private var busy = false
    private var updating: Set<String> = []
    private var editor: ClashModuleEditorSnapshot?
    private var actionFailure: AuthoredText?
    private var actionModuleID: String?
     
    private var settingsFailure: AuthoredText?
    private var settingsModuleID: String?
     
     
    private var panelResults: [String: ModulePanelResult]?
    private var panelsRefreshing: Set<String> = []
    private var panelsFailed: Set<String> = []
    private var certificateFailure: AuthoredText?
     
     
    private var keychainFallback: (certificate: String?, at: ModuleKeychainFallback)?
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []
    private var reloads = 0
     
     
    private var generation = 0
     
     
     
    private var certificateLookedAt: CertificateLook?
    private var readinessWoke = false

    private struct CertificateLook: Equatable {
        var state: ModuleCertificateState
        var unreadable: Bool
    }
     
     
     
     
    private var decryptionCouldWork: Bool?
     
    private var restarting: Task<Void, Never>?
     
    private var turnedOnFor: String?
#if os(iOS)
     
    private var profileServer: ModuleCertificateProfileServer?
#endif
     
     
    var sceneIsActive = true

    init(dependencies: Dependencies?) {
        deps = dependencies
        guard let deps = dependencies else { return }
        let container = deps.container.standardizedFileURL
        for name in [ModuleStore.didChange, ModuleStore.recordsDidChange, ModuleEngineReadinessSource.didChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                 
                 
                guard (note.object as? URL)?.standardizedFileURL == container else { return }
                let fromReadiness = name == ModuleEngineReadinessSource.didChange
                Task { @MainActor [weak self] in
                     
                     
                    if fromReadiness { self?.readinessWoke = true }
                    await self?.reload()
                }
            })
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

     

     
     
    private struct Read: Sendable {
        var certificate: ModuleCertificateState
        var certificateUnreadable: Bool
        var certificateName: String?
        var oldCertificateLeft: String?
        var report: ModuleEngineReport?
        var summary: ModulePublicationSummary?
        var sources: [String: Data]
        var storedValues: [String: String]
        var panelResults: [String: ModulePanelResult]?
    }

     
    private var reading: Task<Void, Never>?
    private var readAgain = false

     
     
     
    func reload() async {
        if let reading {
            readAgain = true
            await reading.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                readAgain = false
                await readOnce()
            } while readAgain
             
             
            reading = nil
        }
        reading = task
        await task.value
    }

    private func readOnce() async {
        guard let deps else {
            snapshot = .off
            details = [:]
            entrySource.set(nil)
            return
        }
        reloads += 1
        let woke = readinessWoke
        readinessWoke = false
        let state: ModuleState
        do {
            state = try await deps.modules.state()
        } catch {
            actionFailure = ModuleStore.authoredText(for: error)
            state = ModuleState()
        }
        var irs: [String: ModuleIR] = [:]
        for record in state.modules {
            if let ir = await deps.modules.publishedModule(record.id) { irs[record.id] = ir }
        }
        let container = deps.container
        let certificates = deps.certificates
        let enabled = state.enabled
         
         
         
        var wanting = ModulePageFacts(platform: deps.platform, state: state)
        wanting.modules = irs
        let asks = enabled || (deps.platform == .ios && ModulePageSnapshotBuilder.wantsDecryption(wanting))
        let ids = state.modules.map(\.id)
         
        let storedKeys = Set(irs.values.flatMap { ir in
            ir.manifest.arguments.compactMap { argument -> String? in
                switch argument.kind {
                case .storedChoice, .storedInput: return argument.name
                case .text, .toggle, .choice, .input: return nil
                }
            }
        })
        let isLeft = deps.isCertificateLeft
        let readsPanels = panelResults == nil


        let read = await Task.detached(priority: .userInitiated) { () -> Read in
            let modules = ModuleLocations(container: container)
            let engine = ModuleEngineLocations(container: container)
            let report = ModuleEngineReport.load(engine)
            var unreadable = false
            var certificate = ModuleCertificateState.notGenerated
            var name: String?
            var oldLeft: String?
             
             
             
            if asks {
                if case .unavailable = ModuleCAFiles.status(engine) {
                    unreadable = true
                } else {
                    certificate = certificates.state(report: report)
                    name = certificates.metadata()?.commonName
                }
                oldLeft = certificates.retiredCertificates().first(where: isLeft).flatMap(ModuleCertificateStore.commonName)
            }
            var sources: [String: Data] = [:]
            for id in ids { sources[id] = try? Data(contentsOf: modules.source(id)) }
            var stored: [String: String] = [:]
            if !storedKeys.isEmpty {
                let store = ModuleScriptStore(directory: container.appendingPathComponent(ModuleScriptStore.directoryName, isDirectory: true),
                                              log: { _ in })
                for key in storedKeys { stored[key] = store.readShared(key: key) }
            }
            return Read(certificate: certificate, certificateUnreadable: unreadable, certificateName: name, oldCertificateLeft: oldLeft,
                        report: report, summary: ModulePublicationSummary.load(locations: modules), sources: sources,
                        storedValues: stored, panelResults: readsPanels ? ModulePanelResults.load(container: container) : nil)
        }.value
        var facts = ModulePageFacts(platform: deps.platform, state: state)
        facts.modules = irs
        facts.certificate = read.certificate
        facts.certificateUnreadable = read.certificateUnreadable
        facts.certificateName = read.certificateName
        facts.oldCertificateLeft = read.oldCertificateLeft
        if let fallback = keychainFallback, fallback.certificate == read.certificateName,
           read.certificate == .notInstalled || read.certificate == .installedNotTrusted {
            facts.keychainFallback = fallback.at
        }
        facts.report = read.report
        facts.summary = read.summary
        facts.actionFailure = actionFailure
        facts.actionModuleID = actionModuleID
        facts.certificateFailure = certificateFailure
        facts.isConnected = deps.isConnected()
        facts.isBusy = busy
        facts.sources = read.sources
        facts.storedValues = read.storedValues
        facts.settingsFailure = settingsFailure
        facts.settingsModuleID = settingsModuleID
        if panelResults == nil { panelResults = read.panelResults ?? [:] }
        withPanels(&facts)
        publish(facts)


        followTheTrust(facts, deps)
         
         
         
         
         
        guard asks else {
            certificateLookedAt = nil
            return
        }
        let look = CertificateLook(state: read.certificate, unreadable: read.certificateUnreadable)
        guard look != certificateLookedAt else { return }
        certificateLookedAt = look
        if !woke, Self.mayAskReadiness(about: deps.container) { deps.readiness.scheduleRecheck() }
    }

     
     
     
     
     
     
     
     
     
     
    private func followTheTrust(_ facts: ModulePageFacts, _ deps: Dependencies) {
         
         
        guard !busy else { return }
        let canWork = facts.state.enabled && facts.certificate == .ready && !facts.certificateUnreadable
        let before = decryptionCouldWork
        decryptionCouldWork = canWork
        if !facts.state.enabled, facts.certificate == .ready, !facts.certificateUnreadable,
           let name = facts.certificateName, turnedOnFor != name,
           ModulePageSnapshotBuilder.wantsDecryption(facts),
           ModuleDecryptionChoice.read(deps.certificates.locations) == .followsTrust {
             
             
            turnedOnFor = name
            ClashLogStore.shared.append("modules: the certificate \(name) is trusted; HTTPS Decryption turns itself on", stream: .app)
            run { try await self.turnDecryptionOn(deps) }
            return
        }
        if canWork, before == false, facts.isConnected { restartOnce(deps) }
    }

     
    private func restartOnce(_ deps: Dependencies) {
        guard restarting == nil else { return }


        ClashLogStore.shared.append(#"modules: HTTPS Decryption can work now; the connection restarts on it once"#, stream: .app)
        let container = deps.container
        let task = Task { @MainActor [weak self] in
            await deps.reconnect(container)
            self?.restarting = nil
        }
        restarting = task
        track(task)
    }

     
     
     
    private func turnDecryptionOn(_ deps: Dependencies) async throws {
        try await deps.modules.setEnabled(true)
        do {
            _ = try await deps.certificates.ensureCertificate(republishing: deps.modules)
        } catch is ModuleCertificateUnavailable {
             
             
        }
        let modules = deps.modules
        track(Task.detached { _ = await modules.refreshDue(announcedAs: nil) })
    }

     
    private func publish(_ facts: ModulePageFacts) {
        generation += 1
        lastFacts = facts
        var page = ModulePageSnapshotBuilder.page(facts, locale: locale)
        page.editor = editor
        snapshot = page
        details = Dictionary(uniqueKeysWithValues: facts.state.modules.map { record in
            (record.id, ModuleDetailBuilder.detail(record: record, facts: facts, source: facts.sources[record.id],
                                                          isUpdating: updating.contains(record.id), locale: locale))
        })
        entrySource.set(ModulePageSnapshotBuilder.entry(facts))
    }

     
     
     
    static func mayAskReadiness(about container: URL) -> Bool {
        guard let group = ClashAppIdentifiers.appGroupContainer,
              group.standardizedFileURL == container.standardizedFileURL else { return true }
        return ModuleEngineReadinessSource.observesInThisProcess
    }

     
    private var lastFacts: ModulePageFacts?

     
     
     
     
    func refreshRuntime() async {
         
         
        guard let deps, lastFacts != nil else { return }
        let mine = generation
        let container = deps.container
        let (report, summary) = await Task.detached(priority: .utility) { () -> (ModuleEngineReport?, ModulePublicationSummary?) in
            (ModuleEngineReport.load(ModuleEngineLocations(container: container)),
             ModulePublicationSummary.load(locations: ModuleLocations(container: container)))
        }.value


         
        guard mine == generation, var facts = lastFacts else { return }
        let connected = deps.isConnected()
        guard report != facts.report || summary != facts.summary || connected != facts.isConnected else { return }
        facts.report = report
        facts.summary = summary
        facts.isConnected = connected
        facts.isBusy = busy
        publish(facts)
    }

     

    func perform(_ action: ClashModulesAction) {
        guard let deps else { return }
        switch action {
        case .setEnabled(let on):
             
             
            ModuleDecryptionChoice.record(on ? .followsTrust : .offByReader, in: deps.certificates.locations)
            run {
                guard on else { return try await deps.modules.setEnabled(false) }
                 
                 
                 
                 
                try await self.turnDecryptionOn(deps)
            }
        case .setModule(let id, let enabled):
            run(module: id) { try await deps.modules.setModule(id, enabled: enabled) }
        case .removeModule(let id):
            run(module: id) { try await deps.modules.remove(id) }
        case .refreshModule(let id):
             
            guard !updating.contains(id) else { return }
            updating.insert(id)
            details[id]?.isUpdating = true
            run(module: id) {
                _ = await deps.modules.refresh(id)
                self.updating.remove(id)
            }
        case .certificate(let kind):
            certificate(kind, deps)
        case .renewCertificate:
             
            run(certificate: true) {
                _ = try await deps.certificates.regenerate(republishing: deps.modules)
                 
                 
                 
                await Self.removeRetired(deps)
            }
        case .notice(.retryAfterMemoryStop):
             
            run { deps.readiness.noteRetry() }
        case .notice(.runScriptAgain):
            break  
        case .newModule:
            editor = ClashModuleEditorSnapshot()
            publishEditor()
        case .editModule(let id):
            let text = (try? Data(contentsOf: ModuleLocations(container: deps.container).source(id)))
                .map { String(decoding: $0, as: UTF8.self) }
            editor = ClashModuleEditorSnapshot(moduleID: id, text: text)
            publishEditor()
        case .saveModule(let id, let text):
            save(id: id, text: text, deps)
        case .closeEditor:
            editor = nil
            publishEditor()
        case .copy(let words):
            deps.copy(words)
        case .setArgument(let id, let name, let value):
             
            run(module: id, settings: true) { try await deps.modules.setArgumentValue(value, for: name, module: id) }
        case .resetArguments(let id):
            run(module: id, settings: true) { try await deps.modules.resetArguments(module: id) }
        case .refreshPanel(let key):
            refreshPanel(key, byReader: true, deps)
        case .panelsAppeared(let id):
            refreshDuePanels(of: id, deps)
        }
    }

     

     
    private static let panelSaves = DispatchQueue(label: "modules.panels.save", qos: .utility)

     
    private func withPanels(_ facts: inout ModulePageFacts) {
        facts.panelResults = panelResults ?? [:]
        facts.panelsRefreshing = panelsRefreshing
        facts.panelsFailed = panelsFailed
    }

     
    private func publishPanels() {
        guard var facts = lastFacts else { return }
        withPanels(&facts)
        publish(facts)
    }

     
    private func panel(_ key: String) -> (module: String, panel: ModulePanel, script: String)? {
        guard let facts = lastFacts else { return nil }
        for record in facts.state.modules where record.enabled {
            for panel in facts.modules[record.id]?.panels ?? [] where ModulePanelResults.key(module: record.id, panel: panel.name) == key {
                guard let script = panel.scriptName else { return nil }
                return (record.id, panel, script)
            }
        }
        return nil
    }

     
     
     
     
    private func refreshPanel(_ key: String, byReader: Bool, _ deps: Dependencies) {
        guard !panelsRefreshing.contains(key), let found = panel(key), deps.isConnected() else { return }
        panelsRefreshing.insert(key)
        panelsFailed.remove(key)
        publishPanels()
        let task = Task { @MainActor in
            let result = await deps.runPanelScript(found.module, found.script, byReader)
            panelsRefreshing.remove(key)
            switch result?.outcome {
            case .done?:
                let given = result?.panel
                var results = panelResults ?? [:]
                results[key] = ModulePanelResult(title: given?.title, content: given?.content, icon: given?.icon,
                                                 iconColor: given?.iconColor, style: given?.style, at: deps.now())
                panelResults = results
                let container = deps.container
                 
                 
                Self.panelSaves.async { ModulePanelResults.save(results, container: container) }
            case .notRun(.tunnelNotConnected)?, .notRun(.busy)?, .notRun(.notFound)?, .notRun(.bodyMissing)?, nil:
                 
                 
                break
            default:
                panelsFailed.insert(key)
            }
            publishPanels()
        }
        track(task)
    }

     
     
     
    private func refreshDuePanels(of id: String, _ deps: Dependencies) {
        guard deps.isConnected(), let facts = lastFacts, let record = facts.state.modules.first(where: { $0.id == id }),
              record.enabled else { return }
        let now = deps.now()
        for panel in facts.modules[id]?.panels ?? [] {
            guard panel.scriptName != nil, let interval = panel.updateInterval else { continue }
            let key = ModulePanelResults.key(module: id, panel: panel.name)
            if let at = panelResults?[key]?.at, now.timeIntervalSince(at) < Double(interval) { continue }
            refreshPanel(key, byReader: false, deps)
        }
    }

    private func certificate(_ kind: ClashModulesSnapshot.CertificateActionKind, _ deps: Dependencies) {
        switch kind {
        case .create:
            run(certificate: true) { _ = try await deps.certificates.ensureCertificate(republishing: deps.modules) }
        case .installProfile:
#if os(iOS)
            installProfile(deps)
#endif
        case .installAndTrust:
            run(certificate: true) { [weak self] in
                 
                 
                 
                let certificates = deps.certificates
                let install = deps.installAndTrust
                let (name, outcome, honoured) = try await Task.detached(priority: .userInitiated) {
                    () throws -> (String?, ModuleCertificateInstallOutcome, Bool) in
                    let file = try certificates.exportFile()
                    let outcome = install(try Data(contentsOf: file))
                    if outcome.added { certificates.noteExported() }
                     
                     
                    let honoured = outcome != .trusted || certificates.isTrusted()
                    return (certificates.metadata()?.commonName, outcome, honoured)
                }.value
                ClashLogStore.shared.append("modules: the certificate \(name ?? "-") install: \(outcome)", stream: .app)
                if case .failed(let at, _) = outcome {
                    self?.keychainFallback = (name, at)
                } else if !honoured {
                     
                     
                    ClashLogStore.shared.append(#"modules: the system took the certificate's trust and this Mac does not trust it yet"#,
                                                stream: .app)
                    self?.keychainFallback = (name, .trust)
                }
                 
                if outcome == .trusted { await Self.removeRetired(deps) }
            }
        case .openInKeychainAccess where keychainFallback?.at == .trust:
            deps.openKeychainAccess()
        case .openInKeychainAccess:
            run(certificate: true) {
                 
                 
                let certificates = deps.certificates
                let file = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    let file = try certificates.exportFile()
                    certificates.noteExported()
                    return file
                }.value
                deps.openCertificateFile(file)
            }
        case .makeNew:
            break  
        }
    }

#if os(iOS)
     
     
     
     
     
     
     
     
     
    private func installProfile(_ deps: Dependencies) {
        ModuleDecryptionChoice.record(.followsTrust, in: deps.certificates.locations)
        profileServer?.stop(.closed)
        profileServer = nil
        run(certificate: true) { [weak self] in
            let certificates = deps.certificates
            let modules = deps.modules
            let enabled = (try? await modules.state())?.enabled ?? false
            if enabled {
                _ = try await certificates.ensureCertificate(republishing: modules)
            }
            let handOut = try await Task.detached(priority: .userInitiated) { () throws -> ModuleCertificateHandOut in
                if !enabled { try certificates.ensureCertificate() }
                return try certificates.handOut()
            }.value
            guard let self else { return }
            let server = deps.profileServer(handOut, { [weak self] in
                certificates.noteExported()
                Task { @MainActor [weak self] in await self?.reload() }
            }, { [weak self] _ in
                Task { @MainActor [weak self] in self?.letGo(of: nil) }
            })
            let page = try await server.start()
            self.profileServer = server
            ClashLogStore.shared.append("modules: the certificate \(handOut.commonName) is offered at \(page.absoluteString)", stream: .app)
            deps.presentProfilePage(page) { [weak self, weak server] in
                server?.stop(.closed)
                self?.letGo(of: server)
            }
        }
    }

     
     
    private func letGo(of server: ModuleCertificateProfileServer?) {
        guard let current = profileServer else { return }
        if let server, current !== server { return }
        if server == nil, current.isListening { return }
        profileServer = nil
    }


#endif

    private func save(id: String?, text: String, _ deps: Dependencies) {
        editor?.isSaving = true
        editor?.refusal = nil
        publishEditor()
        let id = id
        let task = Task { @MainActor in
            do {
                _ = try await deps.modules.saveLocalModule(id: id, text: text)
                editor = nil
            } catch {
                editor?.isSaving = false
                editor?.text = text
                editor?.refusal = ModuleStore.authoredText(for: error).displayText
            }
            await reload()
        }
        track(task)
    }

     
    private func publishEditor() {
        snapshot.editor = editor
    }

     
     
     
    func add(_ input: ModuleAddModuleSheet.Input) async -> Bool {
        guard let deps else { return false }
        isAdding = true
        addRefusal = nil
        defer { isAdding = false }
        do {
            switch input {
            case .link(let link):
                _ = try await deps.modules.add(url: ModuleInstallLink.moduleLink(in: link) ?? link)
            case .text(let text): _ = try await deps.modules.add(text: text)
            }
        } catch {
            addRefusal = ModuleStore.authoredText(for: error).displayText
            return false
        }
        await reload()
        return true
    }

     
    func waitForActions() async {
        while let (id, task) = pending.first {
            await task.value
            pending[id] = nil
        }
    }

     
    var reloadCount: Int { reloads }



     
     
     
     
    private static func removeRetired(_ deps: Dependencies) async {
        let certificates = deps.certificates, remove = deps.removeCertificate
        await Task.detached(priority: .userInitiated) {
            for certificate in certificates.retiredCertificates() {
                let outcome = remove(certificate)
                let name = ModuleCertificateStore.commonName(certificate) ?? "-"
                ClashLogStore.shared.append(#"modules: the replaced certificate \#(name) removal: \#(outcome)"#, stream: .app)
                guard outcome == .removed else { return }
                certificates.forgetRetired(certificate)
            }
        }.value
    }

     
     
     
    private func run(module: String? = nil, certificate: Bool = false, settings: Bool = false,
                     _ work: @escaping () async throws -> Void) {
        busy = true
         
        snapshot.isBusy = true
        actionFailure = nil
        actionModuleID = nil
        certificateFailure = nil
        settingsFailure = nil
        settingsModuleID = nil
        let task = Task { @MainActor in
            do {
                try await work()
            } catch {
                let said = ModuleStore.authoredText(for: error)
                 
                 
                if certificate {
                    certificateFailure = said
                } else if settings, let module {
                    settingsFailure = said
                    settingsModuleID = module
                } else {
                    actionFailure = said
                }
                actionModuleID = module
                ClashLogStore.shared.append("modules page action failed: \(error.localizedDescription)", stream: .app)
            }
            busy = false
            await reload()
        }
        track(task)
    }

    private func track(_ task: Task<Void, Never>) {
        let id = UUID()
        pending[id] = task
        Task { @MainActor [weak self] in
            await task.value
            self?.pending[id] = nil
        }
    }

    nonisolated static func openInSystem(_ url: URL) {
#if canImport(UIKit)
        DispatchQueue.main.async { UIApplication.shared.open(url) }
#elseif canImport(AppKit)
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
#endif
    }

#if os(iOS)
     
     
     
     
     
     
    static func presentInApp(_ page: URL, closed: @escaping @MainActor () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow ?? scenes.first?.keyWindow
        guard var front = window?.rootViewController else {
            openInSystem(page)
            return
        }
        while let next = front.presentedViewController, !next.isBeingDismissed { front = next }
        let safari = SFSafariViewController(url: page)
        safari.dismissButtonStyle = .done
        let closer = ModuleProfilePageCloser(closed)
        safari.delegate = closer
        objc_setAssociatedObject(safari, &ModuleProfilePageCloser.key, closer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        front.present(safari, animated: true)
    }
#endif
}
#if os(iOS)
 
final class ModuleProfilePageCloser: NSObject, SFSafariViewControllerDelegate {
    nonisolated(unsafe) static var key: UInt8 = 0
    private let closed: @MainActor () -> Void

    init(_ closed: @escaping @MainActor () -> Void) {
        self.closed = closed
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        MainActor.assumeIsolated { closed() }
    }
}
#endif
#endif
