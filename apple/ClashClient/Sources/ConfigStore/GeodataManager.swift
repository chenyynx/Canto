import CryptoKit
import Foundation
import Clash

 
 
 
 
 
 
 
final class GeodataManager {
    private static let writeOptions: Data.WritingOptions =
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    private let downloader: HTTPFetching

    init(downloader: HTTPFetching) { self.downloader = downloader }

     
     
     
     
     
    func stage(
        plan: RemoteResourcePlan,
        homeDir: URL,
        maxBytesEach: Int,
        preferBundled: Bool = false,
        reuseExisting: Bool = false,
        validatesWithCore: Bool = true
    ) async throws {
        guard !plan.geodata.isEmpty else { return }
         
         
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        for geo in plan.geodata {
            guard let url = URL(string: geo.url) else { continue }
            let ext = fileExtension(kind: geo.kind, url: url)
            let expectedName = Self.expectedName(kind: geo.kind, ext: ext)
             
             
             
             
             
             
             
            if preferBundled, try BundledGeodataProvisioner.seedIfAvailable(
                fileName: expectedName,
                into: homeDir
            ) {
                continue
            }
            let namedURL = homeDir.appendingPathComponent(expectedName)
             
             
             
             
             
             
             
             
             
             
             
            if reuseExisting,
               Self.readsAsDatabase(at: namedURL, kind: geo.kind, maxBytes: maxBytesEach) {
                continue
            }
             
             
             
             
             
            let result = try await downloader.fetch(
                URLRequest(url: url),
                maxBytes: maxBytesEach,
                redirectPolicy: .followAcrossOrigins(maxHops: 5)
            )
            guard result.data.count <= maxBytesEach else {
                throw DownloadError.tooLarge(result.data.count)
            }
             
             
             
             
             
             
            if let existing = try? Data(contentsOf: namedURL), existing == result.data {
                continue
            }
             
             
             
             
             
            if let reason = Self.rejectionReason(for: result.data, kind: geo.kind) {
                throw DownloadError.invalidPayload(name: expectedName, reason: reason)
            }
            if validatesWithCore, let reason = Self.coreRejectionReason(
                for: result.data,
                kind: geo.kind,
                extension: ext,
                near: homeDir
            ) {
                throw DownloadError.invalidPayload(name: expectedName, reason: reason)
            }
            try result.data.write(to: namedURL, options: Self.writeOptions)
        }
    }

     
     
     
     
     
    static func readsAsDatabase(at url: URL, kind: String, maxBytes: Int) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count <= maxBytes
        else { return false }
        return rejectionReason(for: data, kind: kind) == nil
    }

    private func fileExtension(kind: String, url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        switch kind {
        case "geosite": return "dat"
        case "asn": return "mmdb"
        default: return "metadb"
        }
    }

     
     
     
     
     
     
     
     
     
     
    static func rejectionReason(for data: Data, kind: String) -> String? {
        guard !data.isEmpty else { return "the download was empty" }
         
        let head = data.prefix(64)
        if let text = String(data: head, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for marker in ["<!DOCTYPE", "<html", "<?xml", "{", "["]
            where trimmed.lowercased().hasPrefix(marker.lowercased()) {
                return "the server returned a document, not a database"
            }
        }
         
         
         
         
         
        if kind == "asn", data.count > 4096,
           data.range(of: Self.maxMindMetadataMarker) == nil {
            return "the file is not a MaxMind database"
        }
        return nil
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func coreRejectionReason(
        for data: Data,
        kind: String,
        extension ext: String,
        near homeDir: URL
    ) -> String? {
         
         
         
        let format = ext == "dat" ? "dat" : "mmdb"
        guard ["geoip", "geosite", "asn"].contains(kind),
              !(kind == "geosite" && format == "mmdb")
        else { return nil }

        let candidate = homeDir.appendingPathComponent(
            ".validate-" + UUID().uuidString + "." + format
        )
        defer { try? FileManager.default.removeItem(at: candidate) }
        do {
            try data.write(to: candidate, options: Self.writeOptions)
        } catch {
             
             
            return nil
        }
        var error: NSError?
        AppCore.validateGeodata(kind, format, candidate.path, &error)
        guard let error else { return nil }
        return error.localizedDescription
    }

     
     
     
     
     
     
     
     
     
     
    private static let maxMindMetadataMarker =
        Data([0xAB, 0xCD, 0xEF]) + Data("MaxMind.com".utf8)

     
    static func expectedName(kind: String, ext: String) -> String {
        switch kind {
        case "geoip": return ext == "dat" ? "GeoIP.dat" : "geoip.metadb"
        case "geosite": return "GeoSite.dat"
        case "asn": return "ASN.mmdb"
        default: return "geoip.metadb"
        }
    }
}

 

extension GeodataManager {
     
    static let namedGeodataFiles = ["GeoIP.dat", "GeoSite.dat", "geoip.metadb", "ASN.mmdb"]

     
     
     
     
     
     
     
     
     
    static func staleGeodataBlobs(homeDir: URL) -> [URL] {
        let fm = FileManager.default
        let cacheDir = homeDir.appendingPathComponent("geodata", isDirectory: true)
        let entries = (try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

     
     
    @discardableResult
    static func removeStaleGeodataBlobs(homeDir: URL) -> [URL] {
        let removed = staleGeodataBlobs(homeDir: homeDir).filter { (try? FileManager.default.removeItem(at: $0)) != nil }
        let cacheDir = homeDir.appendingPathComponent("geodata", isDirectory: true)
        if let rest = try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path), rest.isEmpty {
            try? FileManager.default.removeItem(at: cacheDir)
        }
        return removed
    }
}
