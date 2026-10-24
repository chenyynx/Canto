import Darwin
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum LeftoverFiles {
     
    static let temporaryPrefixes = ["core-text-", "import-", "published-rules-"]

     
     
    static let sharedPartialAge: TimeInterval = 10 * 60

     
     
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return Date() }
         
        let started = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
    }()

    private static let lock = NSLock()
    nonisolated(unsafe) private static var swept = false

     
    static func sweepOnce(workingDirectory: URL?, inbox: ProfileShareInbox? = ProfileShareInbox()) {
        lock.lock()
        let first = !swept
        swept = true
        lock.unlock()
        guard first else { return }
        let removed = sweep(temporaryDirectory: FileManager.default.temporaryDirectory,
                            workingDirectory: workingDirectory, inbox: inbox, madeBefore: processStart)
        if !removed.isEmpty {
            ClashLogStore.shared.append("removed \(removed.count) files a stopped App left  "
                + removed.map(\.lastPathComponent).joined(separator: " "), stream: .app)
        }
    }

     
     
     
     
    @discardableResult
    static func sweep(temporaryDirectory: URL, workingDirectory: URL?, inbox: ProfileShareInbox?,
                      madeBefore cutoff: Date, now: Date = Date()) -> [URL] {
        var removed: [URL] = []
        let fm = FileManager.default
        func remove(_ url: URL) {
            if (try? fm.removeItem(at: url)) != nil { removed.append(url) }
        }
         
         
        func madeBeforeCutoff(_ url: URL) -> Bool {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            guard let made = [values?.creationDate, values?.contentModificationDate].compactMap({ $0 }).max() else {
                return false
            }
            return made < cutoff
        }
        for name in (try? fm.contentsOfDirectory(atPath: temporaryDirectory.path)) ?? []
        where temporaryPrefixes.contains(where: name.hasPrefix) {
            let url = temporaryDirectory.appendingPathComponent(name)
            if madeBeforeCutoff(url) { remove(url) }
        }
        if let store = workingDirectory?.appendingPathComponent("store", isDirectory: true) {
            for profile in (try? fm.contentsOfDirectory(atPath: store.path)) ?? [] {
                let folder = store.appendingPathComponent(profile, isDirectory: true)
                for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
                where ConfigurationTextFileLeftovers.isPartial(name) {
                    let url = folder.appendingPathComponent(name)
                    if madeBeforeCutoff(url) { remove(url) }
                }
            }
        }
        if let inbox { removed += inbox.removePartialCopies(olderThan: sharedPartialAge, now: now) }
        return removed
    }
}

 
 
enum ConfigurationTextFileLeftovers {
    static func isPartial(_ name: String) -> Bool {
        name.hasPrefix(".") && name.hasSuffix(".partial")
    }
}
