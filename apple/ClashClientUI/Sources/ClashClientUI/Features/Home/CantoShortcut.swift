import SwiftUI

/// 仪表页快捷方式的类型。
///
/// 只保存英文 key，中文/繁體文案由展示层本地化；模型本身不写用户可见文案。
public enum CantoShortcut:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case nodes
    case requests
    case dnsRecords
    case profiles
    case modules
    case lanShare
    case rules
    case scripts
    case cantoAgent
    case diagnostics

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .nodes: "Nodes"
        case .requests: "Requests"
        case .dnsRecords: "DNS Records"
        case .profiles: "Profiles"
        case .modules: "Modules"
        case .lanShare: "LAN Share"
        case .rules: "Rules"
        case .scripts: "Scripts"
        case .cantoAgent: "Canto Agent"
        case .diagnostics: "Diagnostics"
        }
    }

    public var subtitleKey: String? {
        switch self {
        case .nodes: "Groups and servers"
        case .requests: "Recent requests"
        case .dnsRecords: "Recent DNS queries"
        case .profiles: "Configuration files"
        case .modules: "Rewrites and scripts"
        case .lanShare: "Share on the local network"
        case .rules: "Routing rules"
        case .scripts: "Module scripts"
        case .cantoAgent: "Agent status and pairing"
        case .diagnostics: "Runtime diagnostics"
        }
    }

    public var systemImage: String {
        switch self {
        case .nodes: "server.rack"
        case .requests: "list.bullet"
        case .dnsRecords: "network"
        case .profiles: "doc.text"
        case .modules: "shippingbox"
        case .lanShare: "antenna.radiowaves.left.and.right"
        case .rules: "arrow.triangle.branch"
        case .scripts: "curlybraces"
        case .cantoAgent: "sparkles"
        case .diagnostics: "waveform.path.ecg"
        }
    }

    public var tint: Color {
        switch self {
        case .nodes: .blue
        case .requests: .teal
        case .dnsRecords: .indigo
        case .profiles: .orange
        case .modules: .purple
        case .lanShare: .green
        case .rules: .pink
        case .scripts: .mint
        case .cantoAgent: .cyan
        case .diagnostics: .red
        }
    }

    public static let defaults: [CantoShortcut] = [
        .nodes, .requests, .dnsRecords, .profiles, .modules, .lanShare,
    ]
}
