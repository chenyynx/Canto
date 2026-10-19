import Combine
import Foundation

/// 活动页暂停快照（2026-10-19 随上游新仓库 ClashActivityRequestsPause 文件级搬入）。
///
/// 用途：活动页滚动/查看详情时冻结请求列表，避免高频刷新把正在看的行顶走；
/// ConnectionsModel 在隧道状态变化时调用 `shared.clear()` 让暂停态失效。
public final class HakoActivityRequestsPause: ObservableObject {
    public static let shared = HakoActivityRequestsPause()

    @Published private(set) var held: [HakoActivityRequestSnapshot]?

    var isPaused: Bool { held != nil }

    func rows(live: [HakoActivityRequestSnapshot]) -> [HakoActivityRequestSnapshot] {
        held ?? live
    }

    /// 首次进入暂停时冻结当前列表；后续刷新不再覆盖。
    func hold(_ live: [HakoActivityRequestSnapshot]) {
        if held == nil { held = live }
    }

    func release() { held = nil }

    /// 隧道状态变化时调用：保留"已暂停"语义，但清空内容以便下次重新冻结。
    public func clear() {
        if held != nil { held = [] }
    }
}
