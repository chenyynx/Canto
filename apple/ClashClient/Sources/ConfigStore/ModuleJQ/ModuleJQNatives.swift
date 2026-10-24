#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

enum ModuleJQNative: Hashable {
    case empty, not, path, getpath, setpath, delpaths, has, contains, length, utf8bytelength, type, keys, keysUnsorted
    case tojson, fromjson, tonumber, tostring, startswith, endswith, ltrimstr, rtrimstr, split, explode, implode, strindices
    case sort, sortByImpl, groupByImpl, min, max, minByImpl, maxByImpl, infinite, nan, isinfinite, isnan, isnormal
    case format, matchImpl, env, builtins, input, debug, stderr, inputFilename, inputLineNumber, halt, haltError
    case error, range, getSearchList, frexp, modf, lgammaR
    case math1(String), math2(String), fma
    case unsupportedTime(String)
     
    case map, select, recurse0, recurse1, first, limit, isempty, any0, any1, any2, all0, all1, all2, in1, in2
    case toEntries, fromEntries, withEntries, add, join, repeatForever, reverse, del, asciiDowncase, asciiUpcase
     
    case range3, whileLoop, untilLoop, nwise, combinations, recurse2
     
     
     
    case recurseLoop, recurse2Loop, whileDefinition, untilDefinition

    static let math1Names = [
        "acos", "acosh", "asin", "asinh", "atan", "atanh", "cbrt", "ceil", "cos", "cosh", "exp", "exp10", "exp2", "expm1",
        "fabs", "floor", "gamma", "j0", "j1", "lgamma", "log", "log10", "log1p", "log2", "logb", "nearbyint", "rint",
        "round", "significand", "sin", "sinh", "sqrt", "tan", "tanh", "tgamma", "trunc", "y0", "y1", "erf", "erfc",
    ]
    static let math2Names = [
        "atan2", "copysign", "drem", "fdim", "fmax", "fmin", "fmod", "hypot", "jn", "ldexp", "nextafter", "nexttoward",
        "pow", "remainder", "scalb", "scalbln", "yn",
    ]

    static let byName: [String: ModuleJQNative] = {
        var table: [String: ModuleJQNative] = [
            "empty/0": .empty, "not/0": .not, "path/1": .path, "getpath/1": .getpath, "setpath/2": .setpath,
            "delpaths/1": .delpaths, "has/1": .has, "contains/1": .contains, "length/0": .length,
            "utf8bytelength/0": .utf8bytelength, "type/0": .type, "keys/0": .keys, "keys_unsorted/0": .keysUnsorted,
            "tojson/0": .tojson, "fromjson/0": .fromjson, "tonumber/0": .tonumber, "tostring/0": .tostring,
            "startswith/1": .startswith, "endswith/1": .endswith, "ltrimstr/1": .ltrimstr, "rtrimstr/1": .rtrimstr,
            "split/1": .split, "explode/0": .explode, "implode/0": .implode, "_strindices/1": .strindices,
            "sort/0": .sort, "_sort_by_impl/1": .sortByImpl, "_group_by_impl/1": .groupByImpl, "min/0": .min, "max/0": .max,
            "_min_by_impl/1": .minByImpl, "_max_by_impl/1": .maxByImpl, "infinite/0": .infinite, "nan/0": .nan,
            "isinfinite/0": .isinfinite, "isnan/0": .isnan, "isnormal/0": .isnormal, "format/1": .format,
            "_match_impl/3": .matchImpl, "env/0": .env, "builtins/0": .builtins, "input/0": .input, "debug/0": .debug,
            "stderr/0": .stderr, "input_filename/0": .inputFilename, "input_line_number/0": .inputLineNumber,
            "halt/0": .halt, "halt_error/1": .haltError, "error/0": .error, "range/2": .range,
            "get_search_list/0": .getSearchList, "frexp/0": .frexp, "modf/0": .modf, "lgamma_r/0": .lgammaR, "fma/3": .fma,
            "map/1": .map, "select/1": .select, "recurse/0": .recurse0, "recurse/1": .recurse1, "first/1": .first,
            "limit/2": .limit, "isempty/1": .isempty, "any/0": .any0, "any/1": .any1, "any/2": .any2, "all/0": .all0,
            "all/1": .all1, "all/2": .all2, "IN/1": .in1, "IN/2": .in2, "to_entries/0": .toEntries,
            "from_entries/0": .fromEntries, "with_entries/1": .withEntries, "add/0": .add, "join/1": .join,
            "repeat/1": .repeatForever, "reverse/0": .reverse, "del/1": .del, "ascii_downcase/0": .asciiDowncase,
            "range/3": .range3, "while/2": .whileLoop, "until/2": .untilLoop, "_nwise/1": .nwise, "combinations/0": .combinations,
            "recurse/2": .recurse2,
            "ascii_upcase/0": .asciiUpcase,
        ]
        for name in math1Names { table["\(name)/0"] = .math1(name) }
        for name in math2Names { table["\(name)/2"] = .math2(name) }
        for key in ["now/0", "mktime/0", "gmtime/0", "localtime/0", "strftime/1", "strptime/1", "strflocaltime/1"] {
            table[key] = .unsupportedTime(key)
        }
        return table
    }()

     
     
     
     
     
    static func proved(_ native: ModuleJQNative, _ arguments: [ModuleJQNode]) -> ModuleJQNative {
        switch native {
        case .recurse1:
            return arguments[0].givesAtMostOneOutput ? .recurseLoop : .recurse1
        case .recurse2:
            return arguments[0].givesAtMostOneOutput && arguments[1].isSingle ? .recurse2Loop : .recurse2
        case .whileLoop:
            return arguments[0].isSingle && arguments[1].givesAtMostOneOutput ? .whileLoop : .whileDefinition
        case .untilLoop:
            return arguments[0].isSingle && arguments[1].givesAtMostOneOutput ? .untilLoop : .untilDefinition
        default:
            return native
        }
    }

     
     
     
    func givesOneOutput(_ arguments: [ModuleJQNode]) -> Bool {
        switch self {
        case .map, .withEntries, .del, .isempty, .any1, .any2, .all1, .all2, .in1, .in2:
            return true
        case .not, .length, .utf8bytelength, .type, .keys, .keysUnsorted, .tojson, .fromjson, .tonumber, .tostring, .startswith,
             .endswith, .ltrimstr, .rtrimstr, .split, .explode, .implode, .strindices, .sort, .sortByImpl, .groupByImpl, .min, .max,
             .minByImpl, .maxByImpl, .infinite, .nan, .isinfinite, .isnan, .isnormal, .format, .matchImpl, .env, .builtins,
             .inputFilename, .inputLineNumber, .getSearchList, .frexp, .modf, .lgammaR, .math1, .math2, .fma, .getpath, .setpath,
             .delpaths, .has, .contains, .toEntries, .fromEntries, .add, .join, .reverse, .asciiDowncase, .asciiUpcase, .any0,
             .all0, .debug, .stderr:
            return arguments.allSatisfy(\.givesOneOutput)
        default:
            return false
        }
    }

     
    static let leftOut: Set<String> = ["get_prog_origin", "get_jq_origin", "modulemeta", "import", "include"]
}
#endif
