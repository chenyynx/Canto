import Foundation

 
 
 
 
 
 
 
 
enum ModuleJSONRewriteSyntax {
     
    static let maximumJQBytes = 32 * 1024

     
     
     
     
    enum Verb: Equatable, Sendable {
        case delete, replace, add
        case deleteIfTruthy, replaceIfTruthy, addIfMissingOrNull

        var takesValue: Bool {
            switch self {
            case .delete, .deleteIfTruthy: return false
            case .replace, .add, .replaceIfTruthy, .addIfMissingOrNull: return true
            }
        }

         
         
         
        static func spelled(_ word: String) -> (phase: ModuleRewritePhase, verb: Verb)? {
            var rest = word.lowercased()
            let phase: ModuleRewritePhase
            if rest.hasPrefix("request-") {
                phase = .request
                rest.removeFirst("request-".count)
            } else if rest.hasPrefix("response-") {
                phase = .response
                rest.removeFirst("response-".count)
            } else {
                return nil
            }
            switch rest {
            case "body-json-del": return (phase, .delete)
            case "body-json-replace": return (phase, .replace)
            case "body-json-add": return (phase, .add)
            case "json-del": return (phase, .deleteIfTruthy)
            case "json-replace": return (phase, .replaceIfTruthy)
            case "json-add": return (phase, .addIfMissingOrNull)
            default: return nil
            }
        }
    }

     

     
     
     
     
     
     
     
     
     
     
    static func keyPath(_ text: String) -> [ModuleJSONPathComponent]? {
        var out: [ModuleJSONPathComponent] = []
        let c = Array(text)
        var i = c.count > 1 && c[0] == "." && c[1] != "." ? 1 : 0
        var expectingKey = true
        while i < c.count {
            if c[i] == "[", i + 1 < c.count, c[i + 1] == "\"" || c[i + 1] == "'" {
                let quote = c[i + 1]
                var key = ""
                var j = i + 2
                var closed = false
                while j < c.count {
                    if c[j] == "\\", j + 1 < c.count {
                        key.append(c[j + 1])
                        j += 2
                        continue
                    }
                    if c[j] == quote {
                        closed = true
                        break
                    }
                    key.append(c[j])
                    j += 1
                }
                guard closed, j + 1 < c.count, c[j + 1] == "]" else { return nil }
                out.append(.key(key))
                i = j + 2
                expectingKey = false
                continue
            }
            if c[i] == "[" {
                guard let close = c[i...].firstIndex(of: "]"), close > i + 1 else { return nil }
                let inside = c[(i + 1)..<close]
                if inside.count == 1, inside.first == "*" {
                    out.append(.every)
                } else {
                    guard inside.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(String(inside)) else { return nil }
                    out.append(.index(number))
                }
                i = close + 1
                expectingKey = false
                continue
            }
            if c[i] == "." {
                guard !expectingKey, !out.isEmpty else { return nil }
                expectingKey = true
                i += 1
                continue
            }
            guard expectingKey else { return nil }
            var key = ""
            while i < c.count, c[i] != ".", c[i] != "[" {
                guard c[i] != "]" else { return nil }
                key.append(c[i])
                i += 1
            }
            out.append(.key(key))
            expectingKey = false
        }
        guard !out.isEmpty, !expectingKey else { return nil }
        return out
    }

     

     
     
     
     
    static func value(_ text: String) -> String {
        ModuleJSONText.parse(Data(text.utf8)) == nil ? string(text) : text
    }

     
     
     
     
     
    static func value(ofString text: String) -> String {
        switch ModuleJSONText.parse(Data(text.utf8)) {
        case .object?, .array?: return text
        default: return string(text)
        }
    }

     
    static func string(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }

     

     
     
     
     
     
     
     
    static func operations(_ verb: Verb, paths: [String], values: [String]?) -> Result<[ModuleJSONOperation], ModuleIgnoredReason> {
        guard !paths.isEmpty else { return .failure(.unreadableLine) }
        if verb.takesValue {
            guard let values, values.count == paths.count else { return .failure(.unreadableLine) }
        } else if values != nil {
            return .failure(.unreadableLine)
        }
        var read: [[ModuleJSONPathComponent]] = []
        for text in paths {
            guard let path = keyPath(text) else { return .failure(.unreadableLine) }
            read.append(path)
        }
        if read.contains(where: { $0.contains(.every) }) { return .failure(.noEffectInItsOwnApp(.noEffect)) }
        return .success(read.indices.map { index in
            let path = read[index]
            let json = values.map { value($0[index]) } ?? ""
            switch verb {
            case .delete: return .delete(path)
            case .replace: return .replace(path, valueJSON: json)
            case .add: return .add(path, valueJSON: json)
            case .deleteIfTruthy: return .deleteIfTruthy(path)
            case .replaceIfTruthy: return .replaceIfTruthy(path, valueJSON: json)
            case .addIfMissingOrNull: return .addIfMissingOrNull(path, valueJSON: json)
            }
        })
    }

     

     
     
     
    enum JQSource: Equatable, Sendable {
        case expression(String)
        case file(String)
    }

    static func jqSource(_ written: String) -> JQSource {
        let trimmed = written.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("jq-path=") else { return .expression(written) }
        let address = String(trimmed.dropFirst("jq-path=".count)).trimmingCharacters(in: .whitespaces)
        return .file(unquoted(address) ?? address)
    }

     
     
    static func unquoted(_ text: String) -> String? {
        guard text.count >= 2, let first = text.first, first == "'" || first == "\"", text.last == first else { return nil }
        return String(text.dropFirst().dropLast())
    }

     
     
     
     
     
     
    static func jq(_ expression: String) -> Result<String, ModuleIgnoredReason> {
        guard expression.utf8.count <= maximumJQBytes else { return .failure(.lineTooLong(maximumJQBytes)) }
        do {
            _ = try ModuleJQ.parseOnLargeStack(expression)
            return .success(expression)
        } catch let error as ModuleJQ.ParseError where error.message == ModuleJQ.noProgram {
            return .failure(.noEffectInItsOwnApp(.noEffect))
        } catch let error as ModuleJQ.ParseError {
            return .failure(.jqExpressionInvalid(error.message))
        } catch {
            return .failure(.jqExpressionInvalid("\(error)"))
        }
    }

     
     
     
     
    static func words(_ text: String) -> [String]? {
        var out: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        for character in text {
            if quoted {
                current.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    quoted = false
                }
                continue
            }
            if character == " " || character == "\t" {
                if !current.isEmpty { out.append(current) }
                current = ""
                continue
            }
            if character == "\"", current.isEmpty { quoted = true }
            current.append(character)
        }
        guard !quoted else { return nil }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
