#if os(iOS) || os(macOS)
import Foundation

 
 
 

indirect enum ModuleJQSyntax {
     
    case identity
     
    case recurseDefault
     
     
    case index(ModuleJQSyntax, ModuleJQSyntax)
     
    case slice(ModuleJQSyntax, ModuleJQSyntax?, ModuleJQSyntax?)
     
    case iterate(ModuleJQSyntax)
     
     
     
    case optional(ModuleJQSyntax)
    case literal(ModuleJSONValue)
     
    case string([ModuleJQStringPart], format: String?)
     
    case format(String)
     
    case array(ModuleJQSyntax?)
    case object([ModuleJQObjectEntry])
     
    case negate(ModuleJQSyntax)
     
     
    case pipe([ModuleJQSyntax])
     
    case comma([ModuleJQSyntax])
    case binary(ModuleJQBinaryOperator, ModuleJQSyntax, ModuleJQSyntax)
    case and(ModuleJQSyntax, ModuleJQSyntax)
    case or(ModuleJQSyntax, ModuleJQSyntax)
     
    case alternative(ModuleJQSyntax, ModuleJQSyntax)
     
    case update(ModuleJQUpdateOperator, ModuleJQSyntax, ModuleJQSyntax)
     
    case conditional([(condition: ModuleJQSyntax, then: ModuleJQSyntax)], otherwise: ModuleJQSyntax?)
     
    case tryCatch(ModuleJQSyntax, ModuleJQSyntax?)
    case reduce(source: ModuleJQSyntax, patterns: [ModuleJQPattern], initial: ModuleJQSyntax, update: ModuleJQSyntax)
    case foreach(source: ModuleJQSyntax, patterns: [ModuleJQPattern], initial: ModuleJQSyntax, update: ModuleJQSyntax,
                 extract: ModuleJQSyntax?)
     
    case define(ModuleJQFunctionSyntax, ModuleJQSyntax)
    case call(String, [ModuleJQSyntax])
    case variable(String)
     
    case bind(source: ModuleJQSyntax, patterns: [ModuleJQPattern], body: ModuleJQSyntax)
    case label(String, ModuleJQSyntax)
    case breakLabel(String)
}

enum ModuleJQStringPart {
    case text(String)
    case interpolation(ModuleJQSyntax)
}

enum ModuleJQObjectEntry {
     
    case pair(key: ModuleJQSyntax, value: ModuleJQSyntax)
     
    case keyOnly(ModuleJQSyntax)
}

enum ModuleJQBinaryOperator: String, Sendable {
    case plus = "+", minus = "-", multiply = "*", divide = "/", modulo = "%"
    case equal = "==", notEqual = "!=", less = "<", lessOrEqual = "<=", greater = ">", greaterOrEqual = ">="
}

enum ModuleJQUpdateOperator: Sendable {
     
    case assign
     
    case modify
     
    case arithmetic(ModuleJQBinaryOperator)
     
    case alternative
}

indirect enum ModuleJQPattern {
    case variable(String)
    case array([ModuleJQPattern])
    case object([ModuleJQObjectPatternEntry])

     
    var variables: [String] {
        var names: [String] = []
        func visit(_ pattern: ModuleJQPattern) {
            switch pattern {
            case .variable(let name):
                if !names.contains(name) { names.append(name) }
            case .array(let items):
                items.forEach(visit)
            case .object(let entries):
                for entry in entries {
                    if case .variable(let name) = entry.key, !names.contains(name) { names.append(name) }
                    if let value = entry.pattern { visit(value) }
                }
            }
        }
        visit(self)
        return names
    }
}

struct ModuleJQObjectPatternEntry {
    enum Key {
         
        case variable(String)
         
        case expression(ModuleJQSyntax)
    }

    let key: Key
    let pattern: ModuleJQPattern?
}

struct ModuleJQFunctionSyntax {
    struct Parameter {
        let name: String
         
        let isValue: Bool
    }

    let name: String
    let parameters: [Parameter]
    let body: ModuleJQSyntax
}
#endif
