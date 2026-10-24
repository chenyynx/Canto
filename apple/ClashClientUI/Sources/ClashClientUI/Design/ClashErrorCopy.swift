import ClashClientKit
import Foundation

 
 
 
 
 
public protocol ClashAuthoredError: Error {
    var displayText: ClashDisplayText { get }
}

 
public enum ClashErrorCopy {
     
     
     
     
     
     
    public static func text(_ error: Error) -> ClashDisplayText {
        if let authored = error as? ClashAuthoredError { return authored.displayText }
        if !(type(of: error) is NSError.Type),
           let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            return .copy(description)
        }
        return .verbatim(error.localizedDescription)
    }

     
    public static func message(_ error: Error, locale: Locale) -> String {
        ClashCopy.string(for: text(error), locale: locale)
    }
}

extension ConfigurationLibraryError: ClashAuthoredError {
    public var displayText: ClashDisplayText { .copy(copyKey) }
}
