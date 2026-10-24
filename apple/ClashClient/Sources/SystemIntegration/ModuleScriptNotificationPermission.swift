#if os(iOS) || os(macOS)
import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ModuleScriptNotificationPermission {
     
     
     
    nonisolated static let markers = [#"$notification.post"#, #"$notify("#]
    nonisolated static let askedKey = #"moduleScripts.notifications.asked"#

    static let shared = ModuleScriptNotificationPermission(
        container: ClashAppIdentifiers.appGroupContainer
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("no-app-group", isDirectory: true)
    )

    private let locations: ModuleLocations
    private let defaults: UserDefaults
    private let center: NotificationCenter
    private let isActive: @MainActor () -> Bool
    private let status: @MainActor () async -> UNAuthorizationStatus
    private let request: @MainActor () async -> Void
    private let log: @MainActor (String) -> Void
    private var observer: NSObjectProtocol?
     
     
    private var posting: Set<String>?
    private var asking = false

    init(
        container: URL,
        defaults: UserDefaults = .standard,
        center: NotificationCenter = .default,
        isActive: @escaping @MainActor () -> Bool = ModuleScriptNotificationPermission.appIsInFront,
        status: @escaping @MainActor () async -> UNAuthorizationStatus = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        request: @escaping @MainActor () async -> Void = {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        },
        log: @escaping @MainActor (String) -> Void = { ClashLogStore.shared.append($0, stream: .app, level: .info) }
    ) {
        locations = ModuleLocations(container: container)
        self.defaults = defaults
        self.center = center
        self.isActive = isActive
        self.status = status
        self.request = request
        self.log = log
    }

     
     
    static func appIsInFront() -> Bool {
#if os(iOS)
        UIApplication.shared.applicationState == .active
#else
        NSApplication.shared.isActive
#endif
    }

     
     
    func start() async {
        guard observer == nil else { return }
        let mine = ModuleStore.normalized(locations.container).path
        observer = center.addObserver(forName: ModuleStore.didChange, object: nil, queue: .main) { [weak self] note in
            guard (note.object as? URL).map({ ModuleStore.normalized($0).path }) == mine else { return }
             
            let readersOwn = !ModuleStore.isScheduledRefresh(note)
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.modulesChanged(asking: readersOwn) }
            }
        }
        await modulesChanged(asking: false)
    }

    func stop() {
        observer.map(center.removeObserver)
        observer = nil
    }

     
     
    func modulesChanged(asking: Bool) async {
        let locations = locations
        let now = await Task.detached(priority: .utility) { Self.postingModules(locations) }.value
        let earlier = posting
        posting = now
        guard asking, let earlier, !now.subtracting(earlier).isEmpty else { return }
        await askIfUnanswered()
    }

     
     
     
    func mayShowNotification() async -> Bool {
        if await status() == .notDetermined { await askIfUnanswered() }
        switch await status() {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

     
     
    func askIfUnanswered() async {
        guard !asking, !defaults.bool(forKey: Self.askedKey), isActive() else { return }
        asking = true
        defer { asking = false }
        guard await status() == .notDetermined, isActive(), !defaults.bool(forKey: Self.askedKey) else { return }
        defaults.set(true, forKey: Self.askedKey)
        log(#"module scripts: a script's notification needs Clash's leave; asking for it"#)
        await request()
    }

     
    nonisolated static func postingModules(_ locations: ModuleLocations) -> Set<String> {
        guard let data = try? Data(contentsOf: locations.globalManifest),
              let global = try? ModuleJSON.decoder().decode(ModuleGlobalManifest.self, from: data) else { return [] }
        let needles = markers.map { Data($0.utf8) }
        var out = Set<String>()
        for module in global.modules {
            let files = (try? FileManager.default.contentsOfDirectory(at: locations.scriptsDirectory(module.id),
                                                                     includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "js" {
                guard let body = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
                if needles.contains(where: { body.range(of: $0) != nil }) {
                    out.insert(module.id)
                    break
                }
            }
        }
        return out
    }
}
#endif
