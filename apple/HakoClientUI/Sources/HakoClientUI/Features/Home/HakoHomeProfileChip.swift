import HakoClientKit

 
 
 
 
 
 
 
 
 
public struct HakoHomeProfileChipPresentation: Equatable, Sendable {
    public enum Accessory: Equatable, Sendable {
         
        case picker
         
        case add
    }

    public let title: HakoDisplayText
    public let accessory: Accessory

    public init(title: HakoDisplayText, accessory: Accessory) {
        self.title = title
        self.accessory = accessory
    }
}

public enum HakoHomeProfileChipPresenter {
    public static func presentation(
        selectedProfile: AppleClientProfileSnapshot?,
        isSystemFallback: Bool
    ) -> HakoHomeProfileChipPresentation {
        guard let selectedProfile else {
             
            return .init(title: .copy("Not Set Up"), accessory: .picker)
        }
        if isSystemFallback {
            return .init(title: .copy("Profile Center"), accessory: .add)
        }
         
        return .init(title: .verbatim(selectedProfile.label), accessory: .picker)
    }
}
