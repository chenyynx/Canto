import SwiftUI

 
 
 
enum ClashHomeOutboundModeRowMetrics {
#if os(macOS)
    static let minimumHeight: CGFloat? =
        ClashTheme.Control.compactChoiceRowMinHeight
#else
    static let minimumHeight: CGFloat? = nil
#endif
}
