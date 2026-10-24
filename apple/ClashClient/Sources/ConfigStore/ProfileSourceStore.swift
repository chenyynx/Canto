import CryptoKit
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProfileSourceStore {
     
     
    struct Snapshot {
        let captured: Data?
        let digest: String?
    }

    static func directory(workingDirectory: URL, profileID: String) -> URL {
        workingDirectory.appendingPathComponent("store/\(profileID)", isDirectory: true)
    }

     
     
     
    static func runnableURL(workingDirectory: URL, profileID: String) -> URL {
        directory(workingDirectory: workingDirectory, profileID: profileID)
            .appendingPathComponent("source.yaml")
    }

    static func capturedURL(workingDirectory: URL, profileID: String) -> URL {
        directory(workingDirectory: workingDirectory, profileID: profileID)
            .appendingPathComponent("source.original")
    }

     
    static func digestURL(workingDirectory: URL, profileID: String) -> URL {
        directory(workingDirectory: workingDirectory, profileID: profileID)
            .appendingPathComponent("source.original.digest")
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func store(
        document: String, derivedFrom original: Data,
        workingDirectory: URL, profileID: String
    ) throws {
        let documentBytes = Data(document.utf8)
        try FileManager.default.createDirectory(
            at: directory(workingDirectory: workingDirectory, profileID: profileID),
            withIntermediateDirectories: true
        )
         
         
        try place(
            documentBytes,
            at: runnableURL(workingDirectory: workingDirectory, profileID: profileID)
        )
        guard original != documentBytes else {
            try discardCapture(workingDirectory: workingDirectory, profileID: profileID)
            return
        }
         
         
         
        try place(
            original,
            at: capturedURL(workingDirectory: workingDirectory, profileID: profileID)
        )
        try place(
            Data(digest(of: documentBytes).utf8),
            at: digestURL(workingDirectory: workingDirectory, profileID: profileID)
        )
    }

     
     
     
     
     
     
     
     
     
    static func capturedText(workingDirectory: URL, profileID: String) -> String? {
        guard let runnable = try? Data(
            contentsOf: runnableURL(workingDirectory: workingDirectory, profileID: profileID)
        ) else { return nil }
        guard describesCurrentDocument(
            runnable: runnable, workingDirectory: workingDirectory, profileID: profileID
        ), let captured = try? Data(
            contentsOf: capturedURL(workingDirectory: workingDirectory, profileID: profileID)
        ), let text = String(data: captured, encoding: .utf8) else {
            return String(data: runnable, encoding: .utf8)
        }
        return text
    }

     
     
     
    static func describesCurrentDocument(
        runnable: Data, workingDirectory: URL, profileID: String
    ) -> Bool {
        guard let recorded = try? String(
            contentsOf: digestURL(workingDirectory: workingDirectory, profileID: profileID),
            encoding: .utf8
        ) else { return false }
        return recorded.trimmingCharacters(in: .whitespacesAndNewlines) == digest(of: runnable)
    }

     
    static func snapshot(workingDirectory: URL, profileID: String) -> Snapshot {
        Snapshot(
            captured: try? Data(
                contentsOf: capturedURL(workingDirectory: workingDirectory, profileID: profileID)
            ),
            digest: try? String(
                contentsOf: digestURL(workingDirectory: workingDirectory, profileID: profileID),
                encoding: .utf8
            )
        )
    }

     
     
     
     
     
    static func restore(
        _ snapshot: Snapshot, workingDirectory: URL, profileID: String
    ) {
        try? place(
            snapshot.captured,
            at: capturedURL(workingDirectory: workingDirectory, profileID: profileID)
        )
        try? place(
            snapshot.digest.map { Data($0.utf8) },
            at: digestURL(workingDirectory: workingDirectory, profileID: profileID)
        )
    }

     

     
     
     
     
     
     
    struct Staged {
         
         
        fileprivate let files: [(staged: URL?, target: URL)]
        fileprivate let lock: StagingLock?
    }

    struct Replaced {
        fileprivate var moves: [(target: URL, aside: URL?)]
        fileprivate var lock: StagingLock?
    }

     
     
     
     
     
     
     
     
     
    final class StagingLock: @unchecked Sendable {
        fileprivate let url: URL
        private var fd: Int32
        private let shield: SuspensionShield
        private let shieldToken: Any?

        fileprivate init(url: URL) throws {
            let shield = ConfigResourceStore.suspensionShield
            let token = shield.begin()
            let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { shield.end(token); throw CocoaError(.fileWriteUnknown) }
            guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { close(fd); shield.end(token); throw CocoaError(.fileWriteUnknown) }
            self.url = url
            self.fd = fd
            self.shield = shield
            shieldToken = token
        }

        fileprivate func release() {
            guard fd >= 0 else { return }
            unlink(url.path)
            close(fd)
            fd = -1
            shield.end(shieldToken)
        }

        deinit {
            if fd >= 0 {
                close(fd)
                shield.end(shieldToken)
            }
        }
    }

     
     
    private static func isHeld(_ lock: URL) -> Bool {
        let fd = open(lock.path, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return true }
        flock(fd, LOCK_UN)
        return false
    }

     
     
     
     
    static func sweepAbandonedStaging(in folder: URL, olderThan age: TimeInterval) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        sweepStaging(in: folder, prefixes: [stagedPrefix + "old-"], olderThan: age)
        let tokens = Set(names.filter { $0.hasPrefix(stagedPrefix) && !$0.hasPrefix(stagedPrefix + "old-") }
            .map { String($0.dropFirst(stagedPrefix.count).prefix { $0 != "." }) })
        for token in tokens {
            guard let made = stagingAge(stagedPrefix + token, prefix: stagedPrefix), made >= age,
                  !isHeld(folder.appendingPathComponent(stagedPrefix + token + ".lock")) else { continue }
            for name in names where name.hasPrefix(stagedPrefix + token) {
                try? fm.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    static let stagedPrefix = ".source-staged-"

     
     
     
     
     
    static func stagingName(_ prefix: String) -> String {
        prefix + String(Int64(stagingNow().timeIntervalSince1970 * 1000)) + "-" + UUID().uuidString.lowercased()
    }

    private static func stagingNow() -> Date {


        return Date()
    }



     
    static func stagingAge(_ name: String, prefix: String) -> TimeInterval? {
        guard name.hasPrefix(prefix),
              let millis = Int64(name.dropFirst(prefix.count).prefix { $0 != "-" }) else { return nil }
        return Date().timeIntervalSince1970 - Double(millis) / 1000
    }

     
     
    static func sweepStaging(in directory: URL, prefixes: [String], olderThan age: TimeInterval) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
            guard let made = prefixes.lazy.compactMap({ stagingAge(name, prefix: $0) }).first, made >= age else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

     
    static func stage(
        document: String, derivedFrom original: Data,
        workingDirectory: URL, profileID: String
    ) throws -> Staged {
        let documentBytes = Data(document.utf8)
        let (files, lock) = try stageFiles(workingDirectory: workingDirectory, profileID: profileID) { write in
            var files: [(URL?, URL)] = [(try write(documentBytes, ".yaml"), runnableURL(workingDirectory: workingDirectory, profileID: profileID))]
            if original == documentBytes {
                files += [(nil, capturedURL(workingDirectory: workingDirectory, profileID: profileID)),
                          (nil, digestURL(workingDirectory: workingDirectory, profileID: profileID))]
            } else {
                files += [(try write(original, ".original"), capturedURL(workingDirectory: workingDirectory, profileID: profileID)),
                          (try write(Data(digest(of: documentBytes).utf8), ".digest"),
                           digestURL(workingDirectory: workingDirectory, profileID: profileID))]
            }
            return files
        }
        return Staged(files: files, lock: lock)
    }

     
     
    static func stage(document: String, workingDirectory: URL, profileID: String) throws -> Staged {
        var text = document
         
         
        return try text.withUTF8 { bytes in
            let data = bytes.baseAddress.map {
                Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: $0), count: bytes.count, deallocator: .none)
            } ?? Data()
            let (files, lock) = try stageFiles(workingDirectory: workingDirectory, profileID: profileID) { write in
                [(try write(data, ".yaml") as URL?, runnableURL(workingDirectory: workingDirectory, profileID: profileID))]
            }
            return Staged(files: files, lock: lock)
        }
    }

    private static func stageFiles(
        workingDirectory: URL, profileID: String,
        _ build: ((Data, String) throws -> URL) throws -> [(URL?, URL)]
    ) throws -> (files: [(staged: URL?, target: URL)], lock: StagingLock) {
        let folder = directory(workingDirectory: workingDirectory, profileID: profileID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let token = stagingName("")
         
         
        let lock = try StagingLock(url: folder.appendingPathComponent(stagedPrefix + token + ".lock"))
        var written: [URL] = []
        do {
            let files = try build { data, suffix in
                let url = folder.appendingPathComponent(stagedPrefix + token + suffix)
                try place(data, at: url)
                written.append(url)
                return url
            }
            return (files.map { (staged: $0.0, target: $0.1) }, lock)
        } catch {
            written.forEach { try? FileManager.default.removeItem(at: $0) }
            lock.release()
            throw error
        }
    }

     
     
     
     
     
     
     
    static func swapIn(_ staged: Staged) throws -> Replaced {
        if let folder = staged.files.first?.target.deletingLastPathComponent() {
            sweepAbandonedStaging(in: folder, olderThan: 600)
        }
        var replaced = Replaced(moves: [], lock: staged.lock)
        do {
            for file in staged.files {
                var aside: URL?
                if FileManager.default.fileExists(atPath: file.target.path) {
                    let url = file.target.deletingLastPathComponent()
                        .appendingPathComponent(stagingName(stagedPrefix + "old-"))
                    guard link(file.target.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
                    aside = url
                }
                replaced.moves.append((file.target, aside))
                if let source = file.staged {
                    guard rename(source.path, file.target.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
                } else if aside != nil {
                    guard unlink(file.target.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
                }
            }
        } catch {
            putBack(replaced)
            throw error
        }
        return replaced
    }

     
     
    static func putBack(_ replaced: Replaced) {
        for move in replaced.moves.reversed() {
            if let aside = move.aside {
                _ = rename(aside.path, move.target.path)
            } else {
                _ = unlink(move.target.path)
            }
        }
        replaced.lock?.release()
    }

     
    static func retire(_ replaced: Replaced) {
        for move in replaced.moves { if let aside = move.aside { _ = unlink(aside.path) } }
        replaced.lock?.release()
    }

     
    static func discard(_ staged: Staged) {
        for file in staged.files { if let url = file.staged { _ = unlink(url.path) } }
        staged.lock?.release()
    }

    private static func discardCapture(workingDirectory: URL, profileID: String) throws {
        try place(nil, at: capturedURL(workingDirectory: workingDirectory, profileID: profileID))
        try place(nil, at: digestURL(workingDirectory: workingDirectory, profileID: profileID))
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func place(_ data: Data?, at url: URL) throws {
        guard let data else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

 
 
 
 
 
 
struct ProfileSourceIdentity: Equatable {
    let source: Profile.Source
    let usesLocalSourceOverride: Bool
     
     
     
     
     
     
    let document: String?

    init(_ profile: Profile, workingDirectory: URL) {
        source = profile.source
        usesLocalSourceOverride = profile.usesLocalSourceOverride ?? false
        let path = ProfileSourceStore.runnableURL(workingDirectory: workingDirectory, profileID: profile.id).path
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            document = "\(inode)/\(size)/\(modified)"
        } else {
            document = nil
        }
    }
}
