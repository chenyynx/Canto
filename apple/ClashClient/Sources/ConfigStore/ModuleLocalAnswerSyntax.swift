import Foundation
import UniformTypeIdentifiers

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleLocalAnswerSyntax {
     
    static let maximumInlineBodyBytes = 64 * 1024

     
     
     
     
     
    static func maximumFileBytes(on platform: ModulePlatform) -> Int {
        platform == .mac ? ModuleAnswerFileLimit.macOS : ModuleAnswerFileLimit.iOS
    }

     
    static let pendingFile = ModuleAnswerBody.file(sha256: "", byteCount: 0)

     
     
    static let maximumAddressBytes = ModuleParser.maximumShownBytes

     
    struct Reading: Equatable, Sendable {
        var rule: ModuleRewriteRule
         
        var files: [ModuleAnswerFileReference] = []
         
         
        var notes: [ModuleIgnoredReason] = []
    }

     
    struct PublishedFile: Equatable, Sendable {
        var sha256: String
        var byteCount: Int
    }

    private static let contentTypeName = "Content-Type"
     
     
     
    private static let framing: Set<String> = [
        "content-length", "transfer-encoding", "connection", "upgrade", "keep-alive", "proxy-connection", "te", "trailer",
    ]

     

     
    static let mapLocalKeys: Set<String> = ["data-type", "data", "status-code", "header"]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func mapLocal(_ line: String, origin: ModuleLineOrigin, moduleURL: String?) -> Result<Reading, ModuleIgnoredReason> {
        guard ModuleYAMLText.isOneLine(line), let split = ModuleLineSyntax.splitHead(line, count: 1), !split.head[0].isEmpty,
              let given = keyValues(split.rest, known: mapLocalKeys) else {
            return .failure(.unreadableLine)
        }
        let values = given.values
        var passedOver = given.unknown
        let type = (values["data-type"] ?? "file").lowercased()
        let data = values["data"]
        let status: Int
        if let written = values["status-code"] {
            guard let code = Int(written), (200...999).contains(code) else { return .failure(.unreadableLine) }
            status = code
        } else {
            status = 200
        }
        var written: [ModuleHeaderField] = []
        if let header = values["header"] {
            let read = headerFields(header)
            written = read.fields
            if read.passedOver { passedOver.insert("header", at: 0) }
        }
        var notes: [ModuleIgnoredReason] = passedOver.isEmpty ? [] : [.settingNotSupported(passedOver.joined(separator: ", "))]
        let body: ModuleAnswerBody
        var files: [ModuleAnswerFileReference] = []
        switch type {
        case "text", "json":
            switch inlineBody(data ?? "", base64: false) {
            case .success(let read): body = read
            case .failure(let reason): return .failure(reason)
            }
            if type == "json" { notes.append(.noEffectInItsOwnApp(.anotherAppsFormatWorksHere)) }
        case "tiny-gif":
            body = .tinyGIF
        case "base64":
            switch inlineBody(data ?? "", base64: true) {
            case .success(let read): body = read
            case .failure(let reason): return .failure(reason)
            }
        case "file":
            switch fileAddress(data ?? "", moduleURL: moduleURL, resolvesAgainstTheModule: false) {
            case .success(let address): files = [ModuleAnswerFileReference(url: address, sha256: nil, origin: origin)]
            case .failure(let reason): return .failure(reason)
            }
            body = pendingFile
        default:
            return .failure(.unreadableLine)
        }
        guard let fallback = contentType(dataType: type, path: data) else { return .failure(.unreadableLine) }
        guard ModuleLineSyntax.isValidPattern(split.head[0]) else { return .failure(.invalidPattern) }
        let answer = ModuleLocalAnswer(status: status, headers: withContentType(fallback, written), body: body)
        return .success(Reading(rule: ModuleRewriteRule(pattern: split.head[0], action: .localAnswer(answer), origin: origin),
                                files: files, notes: notes))
    }

     
     
     
     
     
    static func contentType(dataType: String, path: String?) -> String? {
        switch dataType.lowercased() {
        case "text": return "text/plain"
        case "tiny-gif": return "image/gif"
        case "base64": return "application/octet-stream"
        case "json": return "application/json"
        case "file": return path.map(contentType(ofFile:)) ?? "application/octet-stream"
        default: return nil
        }
    }

     
    static let fileTypes: [String: String] = [
        "json": "application/json", "txt": "text/plain", "html": "text/html", "htm": "text/html", "css": "text/css",
        "js": "application/javascript", "xml": "application/xml", "gif": "image/gif", "png": "image/png", "jpg": "image/jpeg",
        "jpeg": "image/jpeg", "webp": "image/webp", "svg": "image/svg+xml", "mp4": "video/mp4",
    ]

     
     
     
    private static func contentType(ofFile path: String) -> String {
        var name = path
        if let url = URL(string: path), url.scheme != nil { name = url.path }
        if let cut = name.firstIndex(where: { $0 == "?" || $0 == "#" }) { name = String(name[..<cut]) }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        if let named = fileTypes[fileExtension] { return named }
        if !fileExtension.isEmpty, let system = UTType(filenameExtension: fileExtension)?.preferredMIMEType { return system }
        return "application/octet-stream"
    }

     
     
     
     
     
    static func headers(_ value: String) -> [ModuleHeaderField]? {
        let read = headerFields(value)
        return read.passedOver ? nil : read.fields
    }

     
     
     
     
     
    static func headerFields(_ value: String) -> (fields: [ModuleHeaderField], passedOver: Bool) {
        if value.isEmpty { return ([], false) }
        let lines: [Substring]
        if value.contains(":") {
            lines = value.split(separator: "|", omittingEmptySubsequences: false)
        } else {
            guard let data = decodedBase64(value), let text = String(data: data, encoding: .utf8) else { return ([], true) }
            lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n")
            guard !lines.isEmpty else { return ([], true) }
        }
        var out: [ModuleHeaderField] = []
        var passedOver = false
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                passedOver = true
                continue
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let field = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard ModuleLoonRewriteSyntax.isHeaderName(name), ModuleYAMLText.isOneLine(field) else {
                passedOver = true
                continue
            }
            out.append(ModuleHeaderField(name: name, value: field))
        }
        return (out, passedOver)
    }

     

     
     
     
     
     
    static func loonMock(type: String, body: String, status: Int?, base64: Bool) -> Result<ModuleLocalAnswer, ModuleIgnoredReason> {
        guard let contentType = ModuleLoonRewriteSyntax.mockContentTypes[type] else { return .failure(.unreadableLine) }
        let code = status ?? 200
        guard (100...599).contains(code) else { return .failure(.unreadableLine) }
        return inlineBody(body, base64: base64).map {
            ModuleLocalAnswer(status: code, headers: [ModuleHeaderField(name: contentTypeName, value: contentType)], body: $0)
        }
    }

     
     
    static func isLoonClassicMock(_ line: String) -> Bool {
        guard let words = ModuleLineSyntax.tokens(line), words.count >= 2 else { return false }
        return ["mock-response-body", "mock-request-body"].contains(words[1].lowercased())
    }

     
    static let loonClassicKeys: Set<String> = ["data-type", "data", "data-path", "mock-data-is-base64", "status-code"]

     
     
     
     
     
     
     
     
     
     
    static func loonClassicMock(_ line: String, origin: ModuleLineOrigin, moduleURL: String?) -> Result<Reading, ModuleIgnoredReason> {
        guard ModuleYAMLText.isOneLine(line), let split = ModuleLineSyntax.splitHead(line, count: 2), !split.head[0].isEmpty else {
            return .failure(.unreadableLine)
        }
        let operation = split.head[1].lowercased()
        let response = operation == "mock-response-body"
        guard response || operation == "mock-request-body", let given = keyValues(split.rest, known: loonClassicKeys) else {
            return .failure(.unreadableLine)
        }
        let values = given.values
        var passedOver = given.unknown
        if !response, values["status-code"] != nil { passedOver.append("status-code") }
        var notes: [ModuleIgnoredReason] = passedOver.isEmpty ? [] : [.settingNotSupported(passedOver.joined(separator: ", "))]
        guard let type = values["data-type"]?.lowercased() else { return .failure(.unreadableLine) }
        let base64: Bool
        switch values["mock-data-is-base64"]?.lowercased() {
        case nil, "false", "0": base64 = false
        case "true", "1": base64 = true
        default: return .failure(.unreadableLine)
        }
        var status = 200
        if response, let written = values["status-code"] {
            guard let code = Int(written), (100...599).contains(code) else { return .failure(.unreadableLine) }
            status = code
        }
        let contentType: String
        let body: ModuleAnswerBody
        var files: [ModuleAnswerFileReference] = []
        func file(_ written: String, base64: Bool) -> ModuleIgnoredReason? {
            switch fileAddress(written, moduleURL: moduleURL, resolvesAgainstTheModule: true) {
            case .success(let address):
                files = [ModuleAnswerFileReference(url: address, sha256: nil, origin: origin, base64: base64 ? true : nil)]
                return nil
            case .failure(let reason):
                return reason
            }
        }
        switch type {
        case "tiny-gif", "base64", "file":
            notes.append(.noEffectInItsOwnApp(.anotherAppsFormatWorksHere))
            if type == "tiny-gif" {
                body = .tinyGIF
            } else if type == "base64" {
                switch inlineBody(values["data"] ?? "", base64: true) {
                case .success(let read): body = read
                case .failure(let reason): return .failure(reason)
                }
            } else {
                guard let written = values["data-path"] ?? values["data"] else { return .failure(.unreadableLine) }
                if let reason = file(written, base64: false) { return .failure(reason) }
                body = pendingFile
            }
            contentType = Self.contentType(dataType: type, path: values["data-path"] ?? values["data"]) ?? "application/octet-stream"
        default:
            guard let named = ModuleLoonRewriteSyntax.mockContentTypes[type] else { return .failure(.unreadableLine) }
            contentType = named
            if let path = values["data-path"] {
                if let reason = file(path, base64: base64) { return .failure(reason) }
                body = pendingFile
            } else {
                switch inlineBody(values["data"] ?? "", base64: base64) {
                case .success(let read): body = read
                case .failure(let reason): return .failure(reason)
                }
            }
        }
        guard ModuleLineSyntax.isValidPattern(split.head[0]) else { return .failure(.invalidPattern) }
        let action: ModuleRewriteAction = response
            ? .localAnswer(ModuleLocalAnswer(status: status, headers: [ModuleHeaderField(name: contentTypeName, value: contentType)], body: body))
            : .requestBody(body, contentType: contentType)
        return .success(Reading(rule: ModuleRewriteRule(pattern: split.head[0], action: action, origin: origin), files: files, notes: notes))
    }

     

     
    static let stashKeys: Set<String> = ["match", "text", "base64", "status-code", "headers"]

     
     
     
     
     
     
     
    static func stashMock(_ item: OrderedJSON, origin: ModuleLineOrigin,
                          fill: (String) -> Result<String, ModuleIgnoredReason>) -> Result<Reading, ModuleIgnoredReason> {
        guard case .object(let pairs) = item else { return .failure(.unreadableLine) }
        func value(_ key: String) -> OrderedJSON? { pairs.first { $0.key == key }?.value }
        func text(_ key: String) -> Result<String?, ModuleIgnoredReason> {
            guard let given = value(key) else { return .success(nil) }
            guard let scalar = ModuleStashParser.scalar(given) else { return .failure(.unreadableLine) }
            return fill(scalar).map { $0 }
        }
        let unknown = pairs.map(\.key).filter { !stashKeys.contains($0) }
        let notes: [ModuleIgnoredReason] = unknown.isEmpty ? [] : [.settingNotSupported(unknown.joined(separator: ", "))]
        do {
            guard let match = try text("match").get(), !match.isEmpty, ModuleYAMLText.isOneLine(match) else {
                return .failure(.unreadableLine)
            }
            let written = try text("text").get(), encoded = try text("base64").get()
            guard written == nil || encoded == nil else { return .failure(.unreadableLine) }
            var status = 200
            if let given = try text("status-code").get() {
                guard let code = Int(given), (200...999).contains(code) else { return .failure(.unreadableLine) }
                status = code
            }
            var headers: [ModuleHeaderField] = []
            if let given = value("headers") {
                guard case .object(let fields) = given else { return .failure(.unreadableLine) }
                for (name, field) in fields {
                    guard let scalar = ModuleStashParser.scalar(field) else { return .failure(.unreadableLine) }
                    let filled = try fill(scalar).get()
                    guard ModuleLoonRewriteSyntax.isHeaderName(name), ModuleYAMLText.isOneLine(filled) else {
                        return .failure(.unreadableLine)
                    }
                    if !framing.contains(name.lowercased()) { headers.append(ModuleHeaderField(name: name, value: filled)) }
                }
            }
            let body: ModuleAnswerBody
            if let written {
                body = try inlineBody(written, base64: false).get()
            } else if let encoded {
                 
                body = try inlineBody(encoded.filter { !$0.isWhitespace }, base64: true).get()
            } else {
                body = .empty
            }
            guard ModuleLineSyntax.isValidPattern(match) else { return .failure(.invalidPattern) }
            let answer = ModuleLocalAnswer(status: status, headers: headers, body: body)
            return .success(Reading(rule: ModuleRewriteRule(pattern: match, action: .localAnswer(answer), origin: origin), notes: notes))
        } catch let reason as ModuleIgnoredReason {
            return .failure(reason)
        } catch {
            return .failure(.unreadableLine)
        }
    }

     

     
     
     
     
     
     
     
     
     
     
    static func fileAddress(_ written: String, moduleURL: String?, resolvesAgainstTheModule: Bool) -> Result<String, ModuleIgnoredReason> {
        guard !written.isEmpty, written.utf8.count <= maximumAddressBytes, ModuleYAMLText.isOneLine(written),
              !written.contains(" ") else {
            return .failure(.unreadableLine)
        }
        if let url = URL(string: written), let scheme = url.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https" else { return .failure(.platformCannot(.remoteRelativeFile)) }
            guard url.host?.isEmpty == false else { return .failure(.unreadableLine) }
            return .success(written)
        }
        let parts = written.split(separator: "/", omittingEmptySubsequences: false)
        guard !written.hasPrefix("/"), !written.hasPrefix("~"), !written.hasPrefix("\\"), !parts.contains("..") else {
            return .failure(.platformCannot(.remoteRelativeFile))
        }
        guard let moduleURL else { return .success(written) }
        guard resolvesAgainstTheModule, let base = URL(string: moduleURL), let resolved = URL(string: written, relativeTo: base)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(), scheme == "http" || scheme == "https", resolved.host?.isEmpty == false else {
            return .failure(.platformCannot(.remoteRelativeFile))
        }
        let address = resolved.absoluteString
        guard address.utf8.count <= maximumAddressBytes else { return .failure(.unreadableLine) }
        return .success(address)
    }

     
     
     
     
     
     
     
     
    static func publishing(_ ir: ModuleIR, files: [String: PublishedFile], platform: ModulePlatform) -> ModuleIR {
        let cap = maximumFileBytes(on: platform)
        var out = ir
        var kept: [ModuleAnswerFileReference] = []
        var setAside: [ModuleLineOrigin] = []
        for var reference in ir.answerFiles {
            guard let file = files[reference.url] else {
                kept.append(reference)
                continue
            }
            guard file.byteCount <= cap else {
                setAside.append(reference.origin)
                out.ignored.append(ModuleIgnoredEntry(text: reference.url, reason: .answerFileTooLarge(cap), origin: reference.origin))
                continue
            }
            reference.sha256 = file.sha256
            kept.append(reference)
            let published = ModuleAnswerBody.file(sha256: file.sha256, byteCount: file.byteCount)
            for index in out.rewriteRules.indices where out.rewriteRules[index].origin == reference.origin {
                out.rewriteRules[index].actions = out.rewriteRules[index].actions.map { action in
                    switch action {
                    case .localAnswer(var answer) where isFile(answer.body):
                        answer.body = published
                        return .localAnswer(answer)
                    case .requestBody(let body, let contentType) where isFile(body):
                        return .requestBody(published, contentType: contentType)
                    default:
                        return action
                    }
                }
            }
        }
        out.rewriteRules.removeAll { rule in
            setAside.contains(rule.origin) && rule.actions.contains { action in
                switch action {
                case .localAnswer(let answer): return isFile(answer.body)
                case .requestBody(let body, _): return isFile(body)
                default: return false
                }
            }
        }
        out.answerFiles = kept
        return out
    }

    private static func isFile(_ body: ModuleAnswerBody) -> Bool {
        if case .file = body { return true } else { return false }
    }

     

     
     
    static func inlineBody(_ text: String, base64: Bool) -> Result<ModuleAnswerBody, ModuleIgnoredReason> {
        if base64 {
            guard let data = decodedBase64(text) else { return .failure(.unreadableLine) }
            guard data.count <= maximumInlineBodyBytes else { return .failure(.lineTooLong(maximumInlineBodyBytes)) }
            return .success(data.isEmpty ? .empty : .bytes(data))
        }
        guard text.utf8.count <= maximumInlineBodyBytes else { return .failure(.lineTooLong(maximumInlineBodyBytes)) }
        return .success(text.isEmpty ? .empty : .text(text))
    }

     
     
     
     
     
     
    static func rawResponse(_ base64: String) -> Result<ModuleLocalAnswer, ModuleIgnoredReason> {
        guard let data = decodedBase64(base64) else { return .failure(.unreadableLine) }
        guard data.count <= maximumInlineBodyBytes else { return .failure(.lineTooLong(maximumInlineBodyBytes)) }
        let ends = [Data("\r\n\r\n".utf8), Data("\n\n".utf8)].compactMap { data.range(of: $0) }
        let end = ends.min { $0.lowerBound < $1.lowerBound }
        let headBytes = end.map { data[..<$0.lowerBound] } ?? data[...]
        let body = end.map { Data(data[$0.upperBound...]) } ?? Data()
        guard let head = String(data: Data(headBytes), encoding: .utf8) else { return .failure(.unreadableLine) }
        var lines = head.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        let statusLine = lines.isEmpty ? [] : lines.removeFirst().split(separator: " ", maxSplits: 2)
        guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/"), let status = Int(statusLine[1]), (100...999).contains(status) else {
            return .failure(.unreadableLine)
        }
        var headers: [ModuleHeaderField] = []
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard ModuleLoonRewriteSyntax.isHeaderName(name), ModuleYAMLText.isOneLine(value),
                  !framing.contains(name.lowercased()) else { continue }
            headers.append(ModuleHeaderField(name: name, value: value))
        }
        return .success(ModuleLocalAnswer(status: status, headers: headers, body: body.isEmpty ? .empty : .bytes(body)))
    }

     
    static func decodedBase64(_ text: String) -> Data? {
        if let data = Data(base64Encoded: text) { return data }
        let remainder = text.utf8.count % 4
        guard remainder == 2 || remainder == 3 else { return nil }
        return Data(base64Encoded: text + String(repeating: "=", count: 4 - remainder))
    }

     
     
     
     
     
     
     
    private static func keyValues(_ text: String, known: Set<String>) -> (values: [String: String], unknown: [String])? {
        guard let pairs = ModuleLineSyntax.quotedParameters(text) else { return nil }
        var values: [String: String] = [:]
        var unknown: [String] = []
        var afterABareQuote = false
        for (key, value, bareQuote) in pairs {
            if known.contains(key) {
                guard values[key] == nil else { return nil }
                values[key] = value
            } else {
                guard !afterABareQuote else { return nil }
                if !unknown.contains(key) { unknown.append(key) }
            }
            afterABareQuote = afterABareQuote || bareQuote
        }
        return (values, unknown)
    }

     
     
    static func withContentType(_ fallback: String, _ written: [ModuleHeaderField]) -> [ModuleHeaderField] {
        let kept = written.filter { !framing.contains($0.name.lowercased()) }
        let named = kept.contains { $0.name.caseInsensitiveCompare(contentTypeName) == .orderedSame }
        return (named ? [] : [ModuleHeaderField(name: contentTypeName, value: fallback)]) + kept
    }
}
