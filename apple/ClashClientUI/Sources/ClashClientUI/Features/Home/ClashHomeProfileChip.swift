import ClashClientKit

 
 
 
 
 
 
 
 
 
public struct ClashHomeProfileChipPresentation: Equatable, Sendable {
    public enum Accessory: Equatable, Sendable {
         
        case picker
         
        case add
    }

    public let title: ClashDisplayText
    public let accessory: Accessory

    public init(title: ClashDisplayText, accessory: Accessory) {
        self.title = title
        self.accessory = accessory
    }
}

public enum ClashHomeProfileChipPresenter {
    public static func presentation(
        selectedProfile: AppleClientProfileSnapshot?,
        isSystemFallback: Bool
    ) -> ClashHomeProfileChipPresentation {
        guard let selectedProfile else {
             
            return .init(title: .copy("Not Set Up"), accessory: .picker)
        }
        if isSystemFallback {
            return .init(title: .copy("Profile Center"), accessory: .add)
        }
         
        return .init(title: .verbatim(selectedProfile.label), accessory: .picker)
    }
}
