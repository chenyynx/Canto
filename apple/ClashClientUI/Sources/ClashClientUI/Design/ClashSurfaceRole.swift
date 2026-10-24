 
 
public enum ClashSurfaceRole: String, CaseIterable, Sendable {
    case primaryPageCard
    case secondaryPageCard
    case groupedSection
    case selection
    case destructiveAction

    public var permitsNativeGlass: Bool {
        self == .primaryPageCard
    }
}

 
 
public enum ClashContentLayoutRole: String, CaseIterable, Sendable {
    case contentColumn
    case primaryRow
    case detailRow
}
