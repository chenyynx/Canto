/// 仪表页的展示数据与动作。
///
/// 视图本身不持有业务状态：连接状态、出站模式、流量数值和快捷方式
/// 都由宿主通过该模型注入，用户操作以闭包回调宿主处理。
public struct CantoDashboardModel {
    /// 顶部品牌字标。
    public var brandTitle: String
    /// 连接开关的当前状态。
    public var isConnected: Bool
    /// 连接开关的无障碍/可见标签。
    public var connectionLabel: String
    /// 模式行主文字（当前出站模式）。
    public var modeTitle: String
    /// 模式行下方的状态说明，例如连接时长；为空时不留空位。
    public var connectionSubtitle: String?
    /// 上传卡标题。
    public var uploadLabel: String
    /// 上传速率的显示值。
    public var uploadValue: String
    /// 上传流量的补充说明（累计量等）。
    public var uploadCaption: String
    /// 下载卡标题。
    public var downloadLabel: String
    /// 下载速率的显示值。
    public var downloadValue: String
    /// 下载流量的补充说明（累计量等）。
    public var downloadCaption: String
    /// 快捷方式分区标题。
    public var shortcutsTitle: String
    /// 快捷方式「编辑」入口标题。
    public var shortcutsEditTitle: String
    /// 当前展示的快捷方式。
    public var shortcuts: [CantoShortcut]
    /// 用户切换连接开关。
    public var onToggleConnection: () -> Void
    /// 用户点击模式行。
    public var onSelectMode: () -> Void
    /// 用户点击快捷方式「编辑」。
    public var onEditShortcuts: () -> Void
    /// 用户点击某个快捷方式。
    public var onShortcut: (CantoShortcut) -> Void

    public init(
        brandTitle: String,
        isConnected: Bool,
        connectionLabel: String,
        modeTitle: String,
        connectionSubtitle: String? = nil,
        uploadLabel: String,
        uploadValue: String,
        uploadCaption: String,
        downloadLabel: String,
        downloadValue: String,
        downloadCaption: String,
        shortcutsTitle: String,
        shortcutsEditTitle: String,
        shortcuts: [CantoShortcut],
        onToggleConnection: @escaping () -> Void,
        onSelectMode: @escaping () -> Void,
        onEditShortcuts: @escaping () -> Void,
        onShortcut: @escaping (CantoShortcut) -> Void
    ) {
        self.brandTitle = brandTitle
        self.isConnected = isConnected
        self.connectionLabel = connectionLabel
        self.modeTitle = modeTitle
        self.connectionSubtitle = connectionSubtitle
        self.uploadLabel = uploadLabel
        self.uploadValue = uploadValue
        self.uploadCaption = uploadCaption
        self.downloadLabel = downloadLabel
        self.downloadValue = downloadValue
        self.downloadCaption = downloadCaption
        self.shortcutsTitle = shortcutsTitle
        self.shortcutsEditTitle = shortcutsEditTitle
        self.shortcuts = shortcuts
        self.onToggleConnection = onToggleConnection
        self.onSelectMode = onSelectMode
        self.onEditShortcuts = onEditShortcuts
        self.onShortcut = onShortcut
    }
}
