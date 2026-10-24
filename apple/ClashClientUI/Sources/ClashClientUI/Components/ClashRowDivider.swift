import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashRowDivider: View {
    private let leadingInset: CGFloat?

     
     
     
    public init(leadingInset: CGFloat? = nil) {
        self.leadingInset = leadingInset
    }

    @ViewBuilder
    public var body: some View {
        if !ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            if let leadingInset {
                Divider().padding(.leading, leadingInset)
            } else {
                Divider()
            }
        }
    }
}
