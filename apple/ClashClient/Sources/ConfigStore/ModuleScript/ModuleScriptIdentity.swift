#if os(iOS) || os(macOS)
import Darwin
import Foundation
import JavaScriptCore

 
 
 
 
struct ModuleScriptEnvironment: Equatable, Sendable {
     
    var system: String
     
    var systemVersion: String
     
    var appVersion: String
    var appBuild: String
    var language: String
     
    var deviceModel: String

    init(system: String, systemVersion: String, appVersion: String, appBuild: String, language: String,
         deviceModel: String) {
        self.system = system
        self.systemVersion = systemVersion.isEmpty ? "1.0" : systemVersion
         
        self.appVersion = appVersion.isEmpty ? "1.0" : appVersion
        self.appBuild = appBuild.isEmpty ? "1" : appBuild
        self.language = language.isEmpty ? "en" : language
        self.deviceModel = deviceModel.isEmpty ? (system == "macOS" ? "Mac" : "iPhone") : deviceModel
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func dictionary(for family: ModuleScriptFamily) -> [String: Any] {
        switch family {
        case .surge, .shadowrocket:
            return ["system": system, "surge-version": appVersion, "surge-build": appBuild, "language": language,
                    "device-model": deviceModel]
        case .stash:
            return ["system": system, "stash-version": appVersion, "stash-build": appBuild, "language": language]
        case .loon:
            return ["params": [String: Any]()]
        case .quantumultX:
            return [:]
        }
    }

     
     
     
     
     
    var loonIdentity: String {
        if system == "macOS" { return #"Mac \#(appVersion)(\#(appBuild))"# }
        let model = deviceModel.hasPrefix("iPhone") || deviceModel.hasPrefix("iPad") ? deviceModel : "iPhone"
        return #"\#(model) \#(systemVersion) \#(appVersion)(\#(appBuild))"#
    }

     
    func loonIdentity(for family: ModuleScriptFamily) -> String? {
        family == .loon ? loonIdentity : nil
    }

     
     
    static func current(
        bundle: Bundle = .main, preferredLanguages: [String] = Locale.preferredLanguages
    ) -> ModuleScriptEnvironment {
        var appURL = bundle.bundleURL
        while appURL.pathExtension != "app", appURL.pathComponents.count > 1 { appURL.deleteLastPathComponent() }
        let app = appURL.pathExtension == "app" ? Bundle(url: appURL) : nil
        let info = app?.infoDictionary ?? bundle.infoDictionary ?? [:]
#if os(macOS)
        let system = "macOS"
#else
        let system = "iOS"
#endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = version.patchVersion > 0
            ? #"\#(version.majorVersion).\#(version.minorVersion).\#(version.patchVersion)"#
            : #"\#(version.majorVersion).\#(version.minorVersion)"#
        return ModuleScriptEnvironment(
            system: system, systemVersion: systemVersion,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "",
            appBuild: info["CFBundleVersion"] as? String ?? "",
            language: preferredLanguages.first ?? "",
            deviceModel: hardwareModel())
    }

     
     
    static func hardwareModel() -> String {
#if targetEnvironment(simulator)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
#endif
#if os(macOS)
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
#else
        var name = utsname()
        uname(&name)
        return withUnsafeBytes(of: &name.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
#endif
    }
}

 
 
enum ModuleScriptIdentity {
     
     
     
     
    static func install(into context: JSContext, family: ModuleScriptFamily, kind: ModuleScriptKind,
                        environment: ModuleScriptEnvironment, scriptPath: String = "") {
        if family == .quantumultX {
            context.setObject(quantumultXEnvironment(scriptPath: scriptPath, environment: environment),
                              forKeyedSubscript: "$environment" as NSString)
        } else if family != .loon || kind == .generic {
            context.setObject(environment.dictionary(for: family), forKeyedSubscript: "$environment" as NSString)
        }
        if let loon = environment.loonIdentity(for: family) {
            context.setObject(loon, forKeyedSubscript: "$loon" as NSString)
        }
    }

     
     
     
     
     
     
     
     
     
     
    static func quantumultXEnvironment(scriptPath: String, environment: ModuleScriptEnvironment) -> [String: Any] {
        var variables: [String: String] = [:]
        if let hash = scriptPath.firstIndex(of: "#") {
            for pair in scriptPath[scriptPath.index(after: hash)...].split(separator: "&") where !pair.isEmpty {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
                if !name.isEmpty, variables[name] == nil { variables[name] = value }
            }
        }
        return ["sourcePath": scriptPath, "variables": variables, "system": environment.system,
                "version": #"\#(environment.appVersion)-build\#(environment.appBuild)"#]
    }

     
     
     
     
     
     
    static func startTime(_ date: Date, family: ModuleScriptFamily) -> Any {
        family == .loon ? date : date.timeIntervalSince1970
    }
}
#endif
