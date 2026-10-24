#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
final class ModuleScriptNotificationRelay {
    static let shared = ModuleScriptNotificationRelay(
        mailbox: ModuleScriptNotificationMailbox.production,
        post: { ModuleScriptNotificationPoster.post($0, log: { ClashLogStore.shared.append($0, stream: .app) }) },
        log: { ClashLogStore.shared.append($0, stream: .app) })

     
    static let freshness: TimeInterval = 600

    private let mailbox: ModuleScriptNotificationMailbox?
    private let freshness: TimeInterval
    private let now: () -> Date
    private let post: (ModuleScriptNotificationRecord) -> Void
    private let log: (String) -> Void
    private var observing = false

    init(
        mailbox: ModuleScriptNotificationMailbox?,
        freshness: TimeInterval = ModuleScriptNotificationRelay.freshness,
        now: @escaping () -> Date = Date.init,
        post: @escaping (ModuleScriptNotificationRecord) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.mailbox = mailbox
        self.freshness = freshness
        self.now = now
        self.post = post
        self.log = log
    }

    deinit { stop() }

    func start() {
        register()
        drain()
    }

    func stop() {
        guard observing, let mailbox else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(mailbox.notificationName as CFString), nil)
        observing = false
    }

     
    @discardableResult
    func drain() -> [ModuleScriptNotificationRecord] {
        guard let mailbox else { return [] }
        let taken = mailbox.takeAll()
        if taken.unreadable > 0 {
            log(#"module script notifications: \#(taken.unreadable) unreadable files removed from the mailbox"#)
        }
        var shown: [ModuleScriptNotificationRecord] = []
        for record in taken.records {
            let age = now().timeIntervalSince(record.at)
            if age > freshness {
                 
                log(#"module script notification from \#(record.scriptName) not shown: posted \#(Int(age)) s ago "#
                    + #"while Clash was not running: \#(record.title) | \#(record.subtitle) | \#(record.body)"#)
            } else {
                post(record)
                shown.append(record)
            }
        }
        return shown
    }

    private static let ring: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let relay = Unmanaged<ModuleScriptNotificationRelay>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async { relay.drain() }
    }

    private func register() {
        guard !observing, let mailbox else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), Self.ring,
            mailbox.notificationName as CFString, nil, .deliverImmediately)
        observing = true
    }
}
#endif
