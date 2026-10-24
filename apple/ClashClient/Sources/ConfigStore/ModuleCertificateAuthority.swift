 
 
 
 
 
 
#if os(iOS) || os(macOS)
import CommonCrypto
import Crypto
import Foundation
import Security
import SwiftASN1
import X509
import _CryptoExtras

 
 
struct ModuleLeaf {
     
    let certificateDER: Data
     
     
     
    let pkcs12: Data
    let passphrase: String
     
    let privateKey: P256.Signing.PrivateKey
}

 
 
 
 
 
 
 
 
enum ModuleCertificateAuthority {
     
     
     
    static let caCommonNamePrefix = #"Clash Module CA"#
     
    static let leafFallbackCommonName = #"Clash Module"#
     
    static let leafLifetime: TimeInterval = 365 * 86_400
     
     
    static let clockSkewAllowance: TimeInterval = 300
     
    private static let commonNameLimit = 64

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

     
     
     
     
     
     
     
    static func caCommonName(madeAt: Date, keyIdentifier: some Sequence<UInt8>) -> String {
        let day = utc.dateComponents([.year, .month, .day], from: madeAt)
        let date = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        let short = keyIdentifier.prefix(3).map { String(format: "%02x", $0) }.joined()
        return caCommonNamePrefix + " " + date + " " + short
    }

     
     
    static func makeCA(now: Date = Date()) throws -> (certificateDER: Data, privateKeyDER: Data) {
        let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let publicKey = Certificate.PublicKey(key.publicKey)
        let keyIdentifier = SubjectKeyIdentifier(hash: publicKey)
        let name = try DistinguishedName { CommonName(caCommonName(madeAt: now, keyIdentifier: keyIdentifier.keyIdentifier)) }
        let notBefore = now.addingTimeInterval(-clockSkewAllowance)
        let notAfter = utc.date(byAdding: .year, value: 10, to: notBefore)!
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: name,
            subject: name,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
                keyIdentifier
            },
            issuerPrivateKey: .init(key))
        return (Data(try serialized(certificate)), key.derRepresentation)
    }

    static func issueLeaf(hostname: String, ca: (certificateDER: Data, privateKeyDER: Data),
                          now: Date = Date()) throws -> ModuleLeaf {
        let name = try subjectAlternativeName(for: hostname)
        let caKey = try _RSA.Signing.PrivateKey(derRepresentation: ca.privateKeyDER)
        let caCertificate = try Certificate(derEncoded: Array(ca.certificateDER))
        let caKeyIdentifier = try caCertificate.extensions.subjectKeyIdentifier?.keyIdentifier
        let leafKey = P256.Signing.PrivateKey()
        let publicKey = Certificate.PublicKey(leafKey.publicKey)
        let notBefore = now.addingTimeInterval(-clockSkewAllowance)
         
         
        let commonName = hostname.utf8.count <= commonNameLimit ? hostname : leafFallbackCommonName
        let leaf = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: publicKey,
            notValidBefore: notBefore,
            notValidAfter: notBefore.addingTimeInterval(leafLifetime),
            issuer: caCertificate.subject,
            subject: try DistinguishedName { CommonName(commonName) },
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true, keyEncipherment: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([name])
                SubjectKeyIdentifier(hash: publicKey)
                if let caKeyIdentifier {
                    AuthorityKeyIdentifier(keyIdentifier: caKeyIdentifier)
                }
            },
            issuerPrivateKey: .init(caKey))
        let certificateDER = try serialized(leaf)
        let passphrase = UUID().uuidString
        let pkcs12 = try ModulePKCS12.encode(certificateDER: certificateDER, privateKey: leafKey,
                                              passphrase: passphrase)
        return ModuleLeaf(certificateDER: Data(certificateDER), pkcs12: Data(pkcs12),
                           passphrase: passphrase, privateKey: leafKey)
    }

     
     
    static func identity(from leaf: ModuleLeaf) throws -> SecIdentity {
        try ModuleIdentity.identity(pkcs12: leaf.pkcs12, passphrase: leaf.passphrase,
                                     certificateDER: leaf.certificateDER, privateKeyX963: leaf.privateKey.x963Representation)
    }

    static var keychainLabelPrefix: String { ModuleIdentity.keychainLabelPrefix }
    static var keychainScope: [CFString: Any] { ModuleIdentity.keychainScope }

    static func keychainIdentity(for leaf: ModuleLeaf) throws -> SecIdentity {
        try ModuleIdentity.keychainIdentity(certificateDER: leaf.certificateDER, privateKeyX963: leaf.privateKey.x963Representation)
    }

     
     
    private static func subjectAlternativeName(for hostname: String) throws -> GeneralName {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, hostname, &v4) == 1 {
            return .ipAddress(ASN1OctetString(contentBytes: withUnsafeBytes(of: &v4) { Array($0) }[...]))
        }
        if inet_pton(AF_INET6, hostname, &v6) == 1 {
            return .ipAddress(ASN1OctetString(contentBytes: withUnsafeBytes(of: &v6) { Array($0) }[...]))
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.".utf8)
        guard !hostname.isEmpty, hostname.utf8.count <= 253, hostname.utf8.allSatisfy(allowed.contains) else {
            throw ModuleCertificateError.invalidHostname(hostname)
        }
        return .dnsName(hostname)
    }

    private static func serialized(_ certificate: Certificate) throws -> [UInt8] {
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        return serializer.serializedBytes
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModulePKCS12 {
    static let iterations = 1

    private static let data: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 7, 1]
    private static let certBag: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 12, 10, 1, 3]
    private static let shroudedKeyBag: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 12, 10, 1, 2]
    private static let x509Certificate: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 9, 22, 1]
    private static let localKeyID: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 9, 21]
    private static let pbeWithSHAAnd3KeyTripleDESCBC: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 12, 1, 3]
    private static let sha1: ASN1ObjectIdentifier = [1, 3, 14, 3, 2, 26]

    static func encode(certificateDER: [UInt8], privateKey: P256.Signing.PrivateKey,
                       passphrase: String) throws -> [UInt8] {
        let password = bmpString(passphrase)
        let keyID = Array(Insecure.SHA1.hash(data: certificateDER))

         
         
        let keySalt = randomBytes(8)
        let encryptedKey = try tripleDESCBC(
            Array(privateKey.derRepresentation),
            key: derive(.key, password: password, salt: keySalt, count: 24),
            iv: derive(.iv, password: password, salt: keySalt, count: 8))

        let safeContents = try der { coder in
            try coder.appendConstructedNode(identifier: .sequence) { coder in
                try coder.appendConstructedNode(identifier: .sequence) { coder in
                    try coder.serialize(certBag)
                    try coder.serialize(explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific) { coder in
                        try coder.appendConstructedNode(identifier: .sequence) { coder in
                            try coder.serialize(x509Certificate)
                            try coder.serialize(ASN1OctetString(contentBytes: certificateDER[...]),
                                                explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific)
                        }
                    }
                    try bagAttributes(&coder, keyID: keyID)
                }
                try coder.appendConstructedNode(identifier: .sequence) { coder in
                    try coder.serialize(shroudedKeyBag)
                    try coder.serialize(explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific) { coder in
                        try coder.appendConstructedNode(identifier: .sequence) { coder in
                            try coder.appendConstructedNode(identifier: .sequence) { coder in
                                try coder.serialize(pbeWithSHAAnd3KeyTripleDESCBC)
                                try coder.appendConstructedNode(identifier: .sequence) { coder in
                                    try coder.serialize(ASN1OctetString(contentBytes: keySalt[...]))
                                    try coder.serialize(iterations)
                                }
                            }
                            try coder.serialize(ASN1OctetString(contentBytes: encryptedKey[...]))
                        }
                    }
                    try bagAttributes(&coder, keyID: keyID)
                }
            }
        }
        let authenticatedSafe = try der { coder in
            try coder.appendConstructedNode(identifier: .sequence) { coder in
                try contentInfo(&coder, data: safeContents)
            }
        }

         
        let macSalt = randomBytes(8)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: authenticatedSafe,
            using: SymmetricKey(data: derive(.mac, password: password, salt: macSalt, count: 20)))

        return try der { coder in
            try coder.appendConstructedNode(identifier: .sequence) { coder in
                try coder.serialize(3)
                try contentInfo(&coder, data: authenticatedSafe)
                try coder.appendConstructedNode(identifier: .sequence) { coder in
                    try coder.appendConstructedNode(identifier: .sequence) { coder in
                        try coder.appendConstructedNode(identifier: .sequence) { coder in
                            try coder.serialize(sha1)
                            try coder.serialize(ASN1Null())
                        }
                        try coder.serialize(ASN1OctetString(contentBytes: Array(mac)[...]))
                    }
                    try coder.serialize(ASN1OctetString(contentBytes: macSalt[...]))
                    try coder.serialize(iterations)
                }
            }
        }
    }

    private static func contentInfo(_ coder: inout DER.Serializer, data content: [UInt8]) throws {
        try coder.appendConstructedNode(identifier: .sequence) { coder in
            try coder.serialize(data)
            try coder.serialize(ASN1OctetString(contentBytes: content[...]),
                                explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific)
        }
    }

     
     
    private static func bagAttributes(_ coder: inout DER.Serializer, keyID: [UInt8]) throws {
        try coder.appendConstructedNode(identifier: .set) { coder in
            try coder.appendConstructedNode(identifier: .sequence) { coder in
                try coder.serialize(localKeyID)
                try coder.appendConstructedNode(identifier: .set) { coder in
                    try coder.serialize(ASN1OctetString(contentBytes: keyID[...]))
                }
            }
        }
    }

     

    enum Purpose: UInt8 { case key = 1, iv = 2, mac = 3 }

    static func derive(_ purpose: Purpose, password: [UInt8], salt: [UInt8], count: Int) -> [UInt8] {
        let u = 20, v = 64
        func repeated(_ bytes: [UInt8]) -> [UInt8] {
            guard !bytes.isEmpty else { return [] }
            return (0..<(v * ((bytes.count + v - 1) / v))).map { bytes[$0 % bytes.count] }
        }
        let diversifier = [UInt8](repeating: purpose.rawValue, count: v)
        var input = repeated(salt) + repeated(password)
        var output: [UInt8] = []
        while true {
            var block = Array(Insecure.SHA1.hash(data: diversifier + input))
            for _ in 1..<iterations { block = Array(Insecure.SHA1.hash(data: block)) }
            output += block
            if output.count >= count { return Array(output.prefix(count)) }
             
            let b = (0..<v).map { block[$0 % u] }
            for start in stride(from: 0, to: input.count, by: v) {
                var carry: UInt16 = 1
                for index in (0..<v).reversed() {
                    let sum = UInt16(input[start + index]) + UInt16(b[index]) + carry
                    input[start + index] = UInt8(truncatingIfNeeded: sum)
                    carry = sum >> 8
                }
            }
        }
    }

     
    static func bmpString(_ string: String) -> [UInt8] {
        string.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] } + [0, 0]
    }

    private static func tripleDESCBC(_ plaintext: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        var ciphertext = [UInt8](repeating: 0, count: plaintext.count + kCCBlockSize3DES)
        var written = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithm3DES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, plaintext, plaintext.count,
                             &ciphertext, ciphertext.count, &written)
        guard status == kCCSuccess else { throw ModuleCertificateError.encryptionFailed(status) }
        return Array(ciphertext.prefix(written))
    }

    private static func randomBytes(_ count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8.random(in: .min ... .max) }
    }

    private static func der(_ body: (inout DER.Serializer) throws -> Void) throws -> [UInt8] {
        var serializer = DER.Serializer()
        try body(&serializer)
        return serializer.serializedBytes
    }
}

 

struct ModuleSwiftCertificatesIssuer: ModuleCertificateIssuing {
    init() {}

    func makeCA(now: Date) throws -> ModuleCAMaterial {
        let ca = try ModuleCertificateAuthority.makeCA(now: now)
        return ModuleCAMaterial(certificateDER: ca.certificateDER, privateKeyDER: ca.privateKeyDER)
    }

    func issueLeaf(hostname: String, ca: ModuleCAMaterial, now: Date) throws -> ModuleLeafMaterial {
        let leaf = try ModuleCertificateAuthority.issueLeaf(
            hostname: hostname, ca: (certificateDER: ca.certificateDER, privateKeyDER: ca.privateKeyDER), now: now)
        let notBefore = now.addingTimeInterval(-ModuleCertificateAuthority.clockSkewAllowance)
        return ModuleLeafMaterial(
            hostname: hostname, certificateDER: leaf.certificateDER, pkcs12: leaf.pkcs12, passphrase: leaf.passphrase,
            privateKeyX963: leaf.privateKey.x963Representation, issuedAt: now,
            notAfter: notBefore.addingTimeInterval(ModuleCertificateAuthority.leafLifetime))
    }
}

#endif
