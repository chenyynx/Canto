import CryptoKit
import Foundation

 
 
 
 
 
 
enum ProviderSeeds {
     
     
     
    static func directory(workingDirectory: URL) -> URL {
        ProviderPayloadStore(workingDirectory: workingDirectory).directory
            .appendingPathComponent("seeds", isDirectory: true)
    }

    static func directory(payloadStore: ProviderPayloadStore) -> URL {
        payloadStore.directory.appendingPathComponent("seeds", isDirectory: true)
    }

     
     
    static let largestBytes = 256 << 20
     
     
    static let unnamedGrace: TimeInterval = 10 * 60
     
    static let partialLifetime: TimeInterval = 60 * 60
    static let partialPrefix = ".partial-"

     
     
     
     
     
    static func place(_ data: Data, in directory: URL) throws -> URL {
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let target = directory.appendingPathComponent(name)
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        if files.fileExists(atPath: target.path) {
            try files.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            return target
        }
        let partial = directory.appendingPathComponent(partialPrefix + UUID().uuidString)
        do {
            try data.write(to: partial, options: [.completeFileProtectionUntilFirstUserAuthentication])
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            try handle.synchronize()
            guard rename(partial.path, target.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? files.removeItem(at: partial)
            throw error
        }
        return target
    }

     
     
     
     
     
     
     
     
    static func place(contentsOf file: URL, in directory: URL, chunkBytes: Int = 1 << 20,
                      rename: (String, String) -> Int32 = { Darwin.rename($0, $1) }) throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        var hasher = SHA256()
        do {
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
             
            while try autoreleasepool(invoking: { () throws -> Bool in
                guard let chunk = try input.read(upToCount: chunkBytes), !chunk.isEmpty else { return false }
                hasher.update(data: chunk)
                return true
            }) {}
        }
        let name = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let target = directory.appendingPathComponent(name)
        if files.fileExists(atPath: target.path) {
            try files.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            try? files.removeItem(at: file)
            return target
        }
        do {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.synchronize()
        }
        if rename(file.path, target.path) == 0 {
             
            try? files.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            return target
        }
        let failure = errno
        guard failure == EXDEV else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure)) }
        let partial = directory.appendingPathComponent(partialPrefix + UUID().uuidString)
        do {
            guard files.createFile(atPath: partial.path, contents: nil,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: partial)
            defer { try? output.close() }
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            while try autoreleasepool(invoking: { () throws -> Bool in
                guard let chunk = try input.read(upToCount: chunkBytes), !chunk.isEmpty else { return false }
                try output.write(contentsOf: chunk)
                return true
            }) {}
            try output.synchronize()
            guard rename(partial.path, target.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? files.removeItem(at: partial)
            throw error
        }
        try? files.removeItem(at: file)
        return target
    }

     
     
    static let referenceMarker = "payloads/seeds/"

    static func named(in texts: [String]) -> Set<String> {
        var names: Set<String> = []
        let marker = referenceMarker
        for text in texts {
            var rest = text[...]
            while let found = rest.range(of: marker) {
                let hex = rest[found.upperBound...].prefix(64)
                if hex.count == 64, hex.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
                    names.insert(String(hex))
                }
                rest = rest[found.upperBound...]
            }
        }
        return names
    }

     
     
     
     
    static func prune(directory: URL, keepingNamedIn texts: [String], now: Date = Date()) {
        prune(directory: directory, keepingNamed: named(in: texts), now: now)
    }

     
     
    static func prune(directory: URL, keepingNamed named: Set<String>, now: Date = Date()) {
        let files = FileManager.default
        guard let entries = try? files.contentsOfDirectory(atPath: directory.path) else { return }
        for name in entries {
            let url = directory.appendingPathComponent(name)
            let modified = (try? files.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date ?? .distantPast
            if name.hasPrefix(partialPrefix) {
                if now.timeIntervalSince(modified) > partialLifetime { try? files.removeItem(at: url) }
                continue
            }
            guard name.count == 64, !named.contains(name),
                  now.timeIntervalSince(modified) >= unnamedGrace else { continue }
            try? files.removeItem(at: url)
        }
    }
}
