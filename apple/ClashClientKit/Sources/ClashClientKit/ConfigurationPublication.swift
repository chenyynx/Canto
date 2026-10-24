import Foundation

 
 
public struct ConfigurationPublicationReference: Codable, Equatable, Hashable, Sendable {
    public let profileID: String
    public let version: String
    public init(profileID: String, version: String = UUID().uuidString) {
        self.profileID = profileID; self.version = version
    }
}

 
 
 
 
 
 
public enum ConfigurationTextFile {
    public static func write(_ text: String, to url: URL) throws {
        let partial = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).partial")
        #if os(iOS) || os(tvOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        guard FileManager.default.createFile(atPath: partial.path, contents: nil, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: partial.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: partial)
            do {
                var text = text
                try text.withUTF8 { try handle.write(contentsOf: UnsafeRawBufferPointer($0)) }
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            guard rename(partial.path, url.path) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path,
                                                               NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)])
            }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }
}

public struct ConfigurationPublicationPayload: Codable, Equatable, Sendable {
    public let reference: ConfigurationPublicationReference
    public let profileMetadata: Data
    public let yaml: String
    public init(reference: ConfigurationPublicationReference, profileMetadata: Data, yaml: String) {
        self.reference = reference; self.profileMetadata = profileMetadata; self.yaml = yaml
    }
}
