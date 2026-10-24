import Compression
import CryptoKit
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct BundledGeodataManifest: Decodable, Equatable {
    struct Resource: Decodable, Equatable {
        let kind: String
        let fileName: String
        let sourceAsset: String
        let downloadURL: String
        let size: Int
        let sha256: String
         
         
        var encoding: String? = nil
         
        var bundledSize: Int? = nil
        var bundledSHA256: String? = nil

        var isCompressed: Bool { encoding == "xz" }
    }

    let schemaVersion: Int
    let upstreamRepository: String
    let upstreamRevision: String
    let releaseTag: String
    let publishedAt: String
    let licenseFile: String
    let resources: [Resource]
}

enum BundledGeodataProvisioningError: LocalizedError, Equatable {
    case missingManifest
    case invalidManifest(String)
    case missingResource(String)
    case sizeMismatch(file: String, expected: Int, actual: Int)
    case checksumMismatch(file: String)
    case decodeFailed(file: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "The built-in Geo data manifest is missing."
        case let .invalidManifest(reason):
            return "The built-in Geo data manifest is invalid: \(reason)"
        case let .missingResource(file):
            return "The built-in Geo data resource \(file) is missing."
        case let .sizeMismatch(file, expected, actual):
            return "The built-in Geo data resource \(file) has size \(actual), expected \(expected)."
        case let .checksumMismatch(file):
            return "The built-in Geo data resource \(file) failed integrity verification."
        case .decodeFailed:
             
             
             
            return "The built-in Geo data resource could not be decoded."
        }
    }

    var failureReason: String? {
        guard case let .decodeFailed(file, reason) = self else { return nil }
        return [file, reason].joined(separator: ": ")
    }
}

 
 
 
enum BundledGeodataProvisioner {
    static let manifestName = "BundledGeoDataManifest"

    static func manifest(in bundle: Bundle = .main) throws -> BundledGeodataManifest {
        guard let url = bundle.url(forResource: manifestName, withExtension: "json") else {
            throw BundledGeodataProvisioningError.missingManifest
        }
        let manifest = try JSONDecoder().decode(
            BundledGeodataManifest.self,
            from: Data(contentsOf: url)
        )
        try validate(manifest)
        return manifest
    }

    static func seedAllMissing(
        into homeDirectory: URL,
        bundle: Bundle = .main
    ) throws {
        let manifest = try manifest(in: bundle)
        try seedMissing(
            manifest.resources,
            into: homeDirectory,
            resourceURL: { bundleURL(for: $0.sourceAsset, in: bundle) }
        )
    }

    static func seedMissing(
        fileNames: Set<String>,
        into homeDirectory: URL,
        bundle: Bundle = .main
    ) throws {
        let manifest = try manifest(in: bundle)
        let selected = manifest.resources.filter { fileNames.contains($0.fileName) }
        guard selected.count == fileNames.count else {
            let known = Set(selected.map(\.fileName))
            let missing = fileNames.subtracting(known).sorted().joined(separator: ", ")
            throw BundledGeodataProvisioningError.invalidManifest(
                "no descriptor for \(missing)"
            )
        }
        try seedMissing(
            selected,
            into: homeDirectory,
            resourceURL: { bundleURL(for: $0.sourceAsset, in: bundle) }
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    static func seedIfAvailable(
        fileName: String,
        into homeDirectory: URL,
        bundle: Bundle = .main
    ) throws -> Bool {
        let manifest = try manifest(in: bundle)
        guard let resource = manifest.resources.first(where: {
            $0.fileName == fileName
        }) else {
            return false
        }
        try seedMissing(
            [resource],
            into: homeDirectory,
            resourceURL: { bundleURL(for: $0.sourceAsset, in: bundle) }
        )
        return true
    }

    static func seedMissing(
        _ resources: [BundledGeodataManifest.Resource],
        into homeDirectory: URL,
        resourceURL: (BundledGeodataManifest.Resource) -> URL?
    ) throws {
        try FileManager.default.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )

        for resource in resources {
            let destination = homeDirectory.appendingPathComponent(resource.fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                continue
            }
            guard let source = resourceURL(resource) else {
                throw BundledGeodataProvisioningError.missingResource(resource.fileName)
            }
            try verify(resource, at: source)

            let temporary = homeDirectory.appendingPathComponent(
                ".\(resource.fileName).\(UUID().uuidString).tmp"
            )
            do {
                if resource.isCompressed {
                     
                     
                    do {
                        try LZMAFileDecoder.decode(
                            from: source, to: temporary, maximumBytes: resource.size
                        )
                    } catch let failure as LZMAFileDecoder.Failure {
                        throw BundledGeodataProvisioningError.decodeFailed(
                            file: resource.fileName, reason: failure.description
                        )
                    }
                    try check(temporary, size: resource.size, sha256: resource.sha256,
                              file: resource.fileName)
                } else {
                    try FileManager.default.copyItem(at: source, to: temporary)
                }
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: temporary.path
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                }
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }
    }

     
     
     
    static func verify(
        _ resource: BundledGeodataManifest.Resource,
        at url: URL
    ) throws {
        if resource.isCompressed {
            try check(url, size: resource.bundledSize ?? -1,
                      sha256: resource.bundledSHA256 ?? "", file: resource.fileName)
        } else {
            try check(url, size: resource.size, sha256: resource.sha256, file: resource.fileName)
        }
    }

    private static func check(_ url: URL, size: Int, sha256: String, file: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actualSize = (attributes[.size] as? NSNumber)?.intValue ?? -1
        guard actualSize == size else {
            throw BundledGeodataProvisioningError.sizeMismatch(
                file: file,
                expected: size,
                actual: actualSize
            )
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == sha256.lowercased() else {
            throw BundledGeodataProvisioningError.checksumMismatch(file: file)
        }
    }

    private static func validate(_ manifest: BundledGeodataManifest) throws {
        guard manifest.schemaVersion == 2 else {
            throw BundledGeodataProvisioningError.invalidManifest(
                "unsupported schema \(manifest.schemaVersion)"
            )
        }
         
         
         
        let known = Set(["GeoIP.dat", "GeoSite.dat", "geoip.metadb", "ASN.mmdb"])
        let names = manifest.resources.map(\.fileName)
        guard !names.isEmpty, Set(names).count == names.count, Set(names).isSubset(of: known) else {
            throw BundledGeodataProvisioningError.invalidManifest(
                "resources must name distinct Core lookup files"
            )
        }
        let hex = "^[0-9a-f]{64}$"
        guard manifest.resources.allSatisfy({ resource in
            resource.fileName == URL(fileURLWithPath: resource.fileName).lastPathComponent
                && resource.sourceAsset == URL(fileURLWithPath: resource.sourceAsset).lastPathComponent
                && URL(string: resource.downloadURL)?.scheme == "https"
                && resource.size > 0
                && resource.sha256.range(of: hex, options: .regularExpression) != nil
                && (resource.encoding == nil || resource.encoding == "xz")
                && (!resource.isCompressed
                    || (resource.sourceAsset.hasSuffix(".xz")
                        && (resource.bundledSize ?? 0) > 0
                        && (resource.bundledSHA256 ?? "").range(of: hex, options: .regularExpression) != nil))
        }) else {
            throw BundledGeodataProvisioningError.invalidManifest(
                "a descriptor has an unsafe name, size, encoding, or SHA-256"
            )
        }
    }

    private static func bundleURL(for asset: String, in bundle: Bundle) -> URL? {
        let path = asset as NSString
        return bundle.url(
            forResource: path.deletingPathExtension,
            withExtension: path.pathExtension
        )
    }
}

 
 
 
 
enum LZMAFileDecoder {
    enum Failure: Error, CustomStringConvertible, Equatable {
        case initialization
        case corrupt(Int32)
        case truncated
        case exceedsExpectedSize(Int)

        var description: String {
            switch self {
            case .initialization: return "the decoder could not be initialised"
            case let .corrupt(status): return "the stream is corrupt (status \(status))"
            case .truncated: return "the stream ends before its end marker"
            case let .exceedsExpectedSize(ceiling): return "the output exceeds the expected \(ceiling) bytes"
            }
        }
    }

    static func decode(from source: URL, to destination: URL, maximumBytes: Int) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        let chunk = 1 << 16
        let inBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { inBuffer.deallocate(); outBuffer.deallocate() }

        var stream = compression_stream(
            dst_ptr: outBuffer, dst_size: chunk,
            src_ptr: UnsafePointer(inBuffer), src_size: 0, state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA)
            == COMPRESSION_STATUS_OK else { throw Failure.initialization }
        defer { compression_stream_destroy(&stream) }

        var atEnd = false
        var written = 0
        while true {
            if stream.src_size == 0 && !atEnd {
                let piece = input.readData(ofLength: chunk)
                if piece.isEmpty {
                    atEnd = true
                } else {
                    piece.copyBytes(to: inBuffer, count: piece.count)
                    stream.src_ptr = UnsafePointer(inBuffer)
                    stream.src_size = piece.count
                }
            }
            stream.dst_ptr = outBuffer
            stream.dst_size = chunk
            let status = compression_stream_process(
                &stream, atEnd ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            )
            let produced = chunk - stream.dst_size
            if produced > 0 {
                written += produced
                guard written <= maximumBytes else { throw Failure.exceedsExpectedSize(maximumBytes) }
                output.write(Data(bytes: outBuffer, count: produced))
            }
            if status == COMPRESSION_STATUS_END { return }
            guard status == COMPRESSION_STATUS_OK else { throw Failure.corrupt(status.rawValue) }
            if atEnd && produced == 0 && stream.src_size == 0 { throw Failure.truncated }
        }
    }
}
