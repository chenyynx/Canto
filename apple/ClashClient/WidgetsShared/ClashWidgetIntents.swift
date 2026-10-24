import AppIntents
import Foundation

 
 
 
 
 

 
 
 
 
 
 
struct ClashWidgetPowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Clash VPN From Widget"
     
     
     
     
     
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "VPN Connected")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        ClashLogStore.shared.append("widget: power tapped → \(value)", stream: .app, level: .info)
        if !value {
             
             
            ClashWidgetMailboxClient.markDisconnected()
        }
        if !(await ClashVPNControlDriver.apply(connect: value)) {
            ClashSystemActionDispatch.enqueue(.vpn(value ? .connect : .disconnect))
        }
         
         
        return .result()
    }
}

 
 
struct ClashWidgetRefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Clash Widget"
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

 
 
 
 
 
struct ClashWidgetSetModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Clash Mode"
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Mode")
    var mode: String

    init() {}

    init(mode: ClashWidgetMode) {
        self.mode = mode.rawValue
    }

    func perform() async throws -> some IntentResult {
        if let mode = ClashWidgetMode(rawValue: mode) {
            do {
                try ClashWidgetMailboxClient.store.writeModeChoice(ClashWidgetModeChoice(mode: mode, at: Date()))
            } catch {
                ClashLogStore.shared.append("widget: mode choice not written  \(error.localizedDescription)", stream: .app, level: .warning)
            }
             
            if await ClashVPNControlDriver.state(journal: false)?.active == true {
                _ = await ClashWidgetMailboxClient.requestAndWait(.setMode(mode), group: nil)
            }
        }
        return .result()
    }
}

 
 
struct ClashWidgetSelectIntent: AppIntent {
    static let title: LocalizedStringResource = "Select Clash Node"
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Group")
    var group: String

    @Parameter(title: "Node")
    var name: String

    init() {}

    init(group: String, name: String) {
        self.group = group
        self.name = name
    }

    func perform() async throws -> some IntentResult {
        _ = await ClashWidgetMailboxClient.requestAndWait(.select(group: group, name: name), group: group)
        return .result()
    }
}

 

 
 
enum ClashWidgetStyle: String, AppEnum {
    case status
    case group
    case stats

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Shows")
    static let caseDisplayRepresentations: [ClashWidgetStyle: DisplayRepresentation] = [
        .status: DisplayRepresentation(title: "Status and Switch"),
        .group: DisplayRepresentation(title: "Proxy Group"),
        .stats: DisplayRepresentation(title: "Network Stats"),
    ]
}

 
 
struct ClashWidgetGroupEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Proxy Group")
    static let defaultQuery = ClashWidgetGroupQuery()

    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct ClashWidgetGroupQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ClashWidgetGroupEntity] {
        identifiers.map(ClashWidgetGroupEntity.init(id:))
    }

    func suggestedEntities() async throws -> [ClashWidgetGroupEntity] {
        (ClashWidgetMailboxClient.store.readAppFacts()?.groups ?? []).map(ClashWidgetGroupEntity.init(id:))
    }

    func defaultResult() async -> ClashWidgetGroupEntity? {
        ClashWidgetMailboxClient.store.readAppFacts()?.firstGroup.map(ClashWidgetGroupEntity.init(id:))
    }
}

struct ClashWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Clash Widget"
    static let description = IntentDescription("What this widget shows.")

    @Parameter(title: "Shows", default: .status)
    var style: ClashWidgetStyle

    @Parameter(title: "Group")
    var group: ClashWidgetGroupEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$style, .equalTo, ClashWidgetStyle.group) {
            Summary("\(\.$style) \(\.$group)")
        } otherwise: {
            Summary("\(\.$style)")
        }
    }
}
