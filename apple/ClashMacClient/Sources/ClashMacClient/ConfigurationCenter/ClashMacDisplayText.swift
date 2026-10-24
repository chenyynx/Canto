import Foundation
import ClashClientUI

extension ClashDisplayText {
     
     
    static func opens(_ key: String, locale: Locale) -> ClashDisplayText {
        .verbatim(ClashCopy.string(key, locale: locale) + "…")
    }

     
     
    static func count(_ count: Int, one: String, other: String) -> ClashDisplayText {
        .format(count == 1 ? one : other, [String(count)])
    }
}
