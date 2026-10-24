import Foundation
import Clash

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum AppCore {
     
     
     
     
     
     
    static func returnFreeMemory() {
        freeMemoryLock.lock()
        defer { freeMemoryLock.unlock() }
        guard !freeMemoryPending else { return }
        freeMemoryPending = true
        freeMemoryQueue.async {
            freeMemoryLock.lock()
            freeMemoryPending = false
            freeMemoryLock.unlock()
            ClashFreeMemory()
        }
    }

     
     
     
     
     
    static func returnFreeMemoryNow(after text: String) {
        guard !Thread.isMainThread, text.utf8.count >= ConfigTransforms.ruleSectionCutFromBytes else { return }
        ClashFreeMemory()
    }

    private static let freeMemoryQueue = DispatchQueue(label: "network.clash.app-core.free-memory", qos: .utility)
    private static let freeMemoryLock = NSLock()
    nonisolated(unsafe) private static var freeMemoryPending = false

    private static let lock = NSRecursiveLock()

    static func exclusive<T>(site: StaticString = #function, _ body: () throws -> T) rethrows -> T {
        let held = acquire(site: site)
        defer { if held { lock.unlock() } }
        note(site)
        return try PerfLedger.measure("core \(site)") { try body() }
    }

     
     
     
    static func exclusiveWaiting<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

     
     
    static func guarded<T>(_ error: NSErrorPointer, cancelled: T, site: StaticString = #function,
                           _ body: () -> T) -> T {
        let held = acquire(site: site)
        defer { if held { lock.unlock() } }
        if Task.isCancelled {
             
             
            error?.pointee = CancellationError() as NSError
            return cancelled
        }
        note(site)
        return PerfLedger.measure("core \(site)") { body() }
    }



    private static func note(_ site: StaticString) {


    }

    private static func acquire(site: StaticString = #function) -> Bool {
        guard Thread.isMainThread, !lock.try() else {
            if !Thread.isMainThread { lock.lock() }
            return true
        }
         
         
        let call = "\(site)"
        ClashLogStore.shared.append("app-core: the main thread waited for a background call  call=\(call)",
                                   stream: .app, level: .warning)
        lock.lock()
        return true
    }

     

    @discardableResult
    static func setup(_ options: ClashSetupOptions, _ error: NSErrorPointer) -> Bool {
        guarded(error, cancelled: false) { ClashSetup(options, error) }
    }

    @discardableResult
    static func checkConfig(_ content: String, _ error: NSErrorPointer) -> Bool {
        guarded(error, cancelled: false) { ClashCheckConfig(content, error) }
    }

    @discardableResult
    static func platformConfigIntentJSON(_ content: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashPlatformConfigIntentJSON(content, error) }
    }

    @discardableResult
    static func validateConfigShape(_ content: String, _ error: NSErrorPointer) -> Bool {
        guarded(error, cancelled: false) { ClashValidateConfigShape(content, error) }
    }

    @discardableResult
    static func invalidDomainPatternsJSON(_ content: String, _ profile: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashInvalidDomainPatternsJSON(content, profile, error) }
    }

    @discardableResult
    static func mergeOverride(_ raw: String, _ overrideJSON: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashMergeOverrideForIOS(raw, overrideJSON, error) }
    }

     
     
     

    @discardableResult
    static func editYAML(_ original: String, _ pathJSON: String, _ op: String, _ valueJSON: String,
                         _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashEditYAMLForIOS(original, pathJSON, op, valueJSON, error) }
    }

     
     
     
    @discardableResult
    static func editYAMLWithOptions(_ original: String, _ pathJSON: String, _ op: String, _ valueJSON: String,
                                    _ optionsJSON: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) {
            ClashEditYAMLForIOSWithOptions(original, pathJSON, op, valueJSON, optionsJSON, error)
        }
    }

     
     
     
     
    static func policyNamesJSON(_ content: String, _ error: NSErrorPointer) -> String {
        guarded(error, cancelled: "{}") { ClashPolicyNamesJSON(content, error) }
    }

     
     
    static func providerAgeSecretKeysJSON(_ content: String, _ error: NSErrorPointer) -> String {
        guarded(error, cancelled: "{}") { ClashProviderAgeSecretKeysJSON(content, error) }
    }

     
     
     
    @discardableResult
    static func yamlToJSONWithOptions(_ text: String, _ optionsJSON: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashYamlToJSONWithOptions(text, optionsJSON, error) }
    }

    @discardableResult
    static func renameReferences(_ original: String, _ kind: String, _ oldName: String, _ newName: String,
                                 _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashRenameReferencesForIOS(original, kind, oldName, newName, error) }
    }

    @discardableResult
    static func validateItem(_ kind: String, _ item: String, _ context: String,
                             _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashValidateItemForIOS(kind, item, context, error) }
    }

    @discardableResult
    static func matchRule(_ document: String, _ resourceMapJSON: String, _ query: String,
                          _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashMatchRuleForIOS(document, resourceMapJSON, query, error) }
    }

    @discardableResult
    static func configDeviationsJSON(_ content: String, _ profile: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashConfigDeviationsJSON(content, profile, error) }
    }

    @discardableResult
    static func planResources(_ merged: String, _ profile: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashPlanResourcesForProfile(merged, profile, error) }
    }

    @discardableResult
    static func proxyCatalog(_ content: String, _ resourceMapJSON: String, _ selectionsJSON: String,
                             _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashProxyCatalogForIOS(content, resourceMapJSON, selectionsJSON, error) }
    }

     
    @discardableResult
    static func syntaxCatalog(_ targetProfile: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashSyntaxCatalogForIOS(targetProfile, error) }
    }

     
    @discardableResult
    static func yamlOutline(_ original: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashYAMLOutlineForIOS(original, error) }
    }

    @discardableResult
    static func ruleProviderCatalog(_ content: String, _ resourceMapJSON: String, _ compileRuleSets: Bool,
                                    _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashRuleProviderCatalogForIOS(content, resourceMapJSON, compileRuleSets, error) }
    }

     
     
     
    @discardableResult
    static func compileCheck(_ document: String, _ resourceMapJSON: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashCompileCheckForIOS(document, resourceMapJSON, error) }
    }

    @discardableResult
    static func finalize(_ merged: String, _ resourceMapJSON: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashFinalizeForIOS(merged, resourceMapJSON, error) }
    }

     
     
     
     

    @discardableResult
    static func validateConfigShapeAtPath(_ path: String, _ error: NSErrorPointer) -> Bool {
        guarded(error, cancelled: false) { ClashValidateConfigShapeAtPath(path, error) }
    }

    @discardableResult
    static func planResourcesAtPath(_ path: String, _ profile: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashPlanResourcesForProfileAtPath(path, profile, error) }
    }

    static func providerAgeSecretKeysJSONAtPath(_ path: String, _ error: NSErrorPointer) -> String {
        guarded(error, cancelled: "{}") { ClashProviderAgeSecretKeysJSONAtPath(path, error) }
    }

    @discardableResult
    static func finalizeAtPath(_ path: String, _ resourceMapJSON: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashFinalizeForIOSAtPath(path, resourceMapJSON, error) }
    }



     
     
    @discardableResult
    static func finalizeWithOptionsAtPath(_ path: String, _ resourceMapJSON: String, _ optionsJSON: String,
                                          _ error: NSErrorPointer) -> ClashStringBox? {
        let box = guarded(error, cancelled: nil) { ClashFinalizeForIOSWithOptionsAtPath(path, resourceMapJSON, optionsJSON, error) }


        return box
    }

     
     
     
    @discardableResult
    static func finalizeWithOptions(_ merged: String, _ resourceMapJSON: String, _ optionsJSON: String,
                                    _ error: NSErrorPointer) -> ClashStringBox? {
        let box = guarded(error, cancelled: nil) { ClashFinalizeForIOSWithOptions(merged, resourceMapJSON, optionsJSON, error) }


        return box
    }

    @discardableResult
    static func inspectProvider(_ kind: String, _ behavior: String, _ format: String, _ payload: Data,
                                _ count: UnsafeMutablePointer<Int>, _ error: NSErrorPointer) -> Bool {
        guarded(error, cancelled: false) { ClashInspectProviderForIOS(kind, behavior, format, payload, count, error) }
    }

    @discardableResult
    static func decryptAge(_ payload: Data, _ key: String, _ error: NSErrorPointer) -> Data? {
        guarded(error, cancelled: nil) { ClashDecryptAgeForIOS(payload, key, error) }
    }

    @discardableResult
    static func stageProvidersForPublish(_ content: String, _ profile: String, _ compileRuleSets: Bool,
                                         _ error: NSErrorPointer) -> Bool {
        guarded(error, cancelled: false) { ClashStageProvidersForPublish(content, profile, compileRuleSets, error) }
    }

#if os(tvOS)
     
     
    static func preparePendingProviderSeeds(_ content: String, _ profile: String, _ error: NSErrorPointer) -> String {
        guarded(error, cancelled: "[]") { ClashPreparePendingProviderSeeds(content, profile, error) }
    }
#endif

    @discardableResult
    static func inspectProxyPayload(_ payload: Data, _ context: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashInspectProxyPayloadForIOS(payload, context, error) }
    }

    @discardableResult
    static func compileRuleProvider(_ sourcePath: String, _ behavior: String, _ format: String, _ outputPath: String,
                                    _ error: NSErrorPointer) -> ClashRuleProviderCompileResult? {
        guarded(error, cancelled: nil) { ClashCompileRuleProvider(sourcePath, behavior, format, outputPath, error) }
    }

    @discardableResult
    static func validateGeodata(_ kind: String, _ format: String, _ path: String, _ error: NSErrorPointer) -> Bool {
        guarded(error, cancelled: false) { ClashValidateGeodataForIOS(kind, format, path, error) }
    }

    @discardableResult
    static func prepareGeoIPCache(_ content: String, _ geodataMode: Bool, _ error: NSErrorPointer) -> String {
        guarded(error, cancelled: "") { ClashPrepareGeoIPCache(content, geodataMode, error) }
    }

    @discardableResult
    static func prepareGeoSiteCache(_ content: String, _ error: NSErrorPointer) -> String {
        guarded(error, cancelled: "") { ClashPrepareGeoSiteCache(content, error) }
    }

    @discardableResult
    static func readProxyPayload(_ payload: Data, _ context: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashReadProxyPayloadForIOS(payload, context, error) }
    }

     
     
     
    @discardableResult
    static func inspectProxyPayloadSummary(_ payload: Data, _ context: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashInspectProxyPayloadSummaryForIOS(payload, context, error) }
    }

     
     
     
    @discardableResult
    static func openNodeCatalog(_ content: String, _ resourceMapJSON: String, _ selectionsJSON: String,
                                _ error: NSErrorPointer) -> ClashNodeCatalog? {
        guarded(error, cancelled: nil) { ClashOpenNodeCatalogForIOS(content, resourceMapJSON, selectionsJSON, error) }
    }

     
     
     
     
    @discardableResult
    static func openPublishedRuleCatalog(_ path: String, _ error: NSErrorPointer) -> ClashPublishedRuleCatalog? {
        guarded(error, cancelled: nil) { ClashOpenRuleCatalogForPublishedAtPath(path, error) }
    }

     
     
     
     
     
    @discardableResult
    static func openRuleCatalogAtPath(_ path: String, _ error: NSErrorPointer) -> ClashRuleCatalog? {
        guarded(error, cancelled: nil) { ClashOpenRuleCatalogForIOSAtPath(path, error) }
    }

     
     
     
     
     
     
     
     
    static func nodeConfigJSON(_ catalog: ClashNodeCatalog, provider: String, name: String) -> String {
        exclusive { catalog.nodeConfigJSON(provider, name: name) }
    }

     
     
     
    @discardableResult
    static func openProxyPayload(_ payload: Data, _ context: String, _ error: NSErrorPointer) -> ClashProxyPayload? {
        guarded(error, cancelled: nil) { ClashOpenProxyPayloadForIOS(payload, context, error) }
    }

     
    @discardableResult
    static func readProxyPayloadSummary(_ payload: Data, _ context: String, _ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashReadProxyPayloadSummaryForIOS(payload, context, error) }
    }

    @discardableResult
    static func updateAppPolicy(_ options: ClashAppPolicyOptions, _ error: NSErrorPointer) -> Bool {
        guarded(error, cancelled: false) { ClashUpdateAppPolicy(options, error) }
    }

    @discardableResult
    static func consumeGoCrashReport(_ error: NSErrorPointer) -> ClashStringBox? {
        guarded(error, cancelled: nil) { ClashConsumeGoCrashReport(error) }
    }

    @discardableResult
    static func geodataModeEnabled(_ content: String) -> Bool {
        exclusive { ClashGeodataModeEnabled(content) }
    }

    @discardableResult
    static func geoIPCountryLines(_ content: String) -> String {
        exclusive { ClashGeoIPCountryLines(content) }
    }

    @discardableResult
    static func geoSiteCategoryLines(_ content: String) -> String {
        exclusive { ClashGeoSiteCategoryLines(content) }
    }
}

 
 
 
 
enum PerfLedger {



     
     
     
    @inline(__always)
    static func asJob<T>(_ name: String, _ body: () throws -> T) rethrows -> T {

        return try body()

    }

     
     
    struct Laps {


        init() {}

        @inline(__always)
        mutating func mark(_ name: @autoclosure () -> String) {


        }
    }

    @inline(__always)
    static func measure<T>(_ name: @autoclosure () -> String, _ body: () throws -> T) rethrows -> T {


        return try body()
    }

    @inline(__always)
    static func measure<T>(_ name: @autoclosure () -> String, _ body: () async throws -> T) async rethrows -> T {


        return try await body()
    }
}
