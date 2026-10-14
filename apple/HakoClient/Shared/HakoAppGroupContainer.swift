import Foundation

extension HakoAppIdentifiers {

    static let appGroupContainer: URL? = {
        // 1. 内建 group（Xcode 正常签名即命中，行为与上游一致）
        let builtin = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        // 2. 重签适配：签名 entitlements 里实际授权的 group
        let root = builtin ?? resolvedAppGroupContainer
#if os(tvOS)
        let resolved = root?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
#else
        let resolved = root
#endif
        // 3. Sideload 兜底（无任何 App Group entitlement）：降级到 App 沙盒
        // Documents/HakoAppGroup。注意：App 与 NE 扩展进程各自解析到各自
        // 沙盒，配置互不可见 → 隧道扩展必然起不来（「隧道提供方报告错误」）。
        // 该分支仅兜主 App 不崩，VPN 功能需签名带 App Group 才可用。
        if let resolved { return resolved }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fallback = docs.appendingPathComponent("HakoAppGroup", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()

    /// 仅返回签名实际授权的 group 容器（内建优先，其次 entitlements 候选），
    /// 不做 Documents 降级。供需要"确认真共享容器"的调用方使用。
    static var resolvedAppGroupContainer: URL? {
        // 1. 内建 group
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            return url
        }
        // 2. 签名 entitlements 里的候选
        for candidate in signedAppGroupCandidates() {
            if let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: candidate
            ) {
                return url
            }
        }
        // 3. 无可用 group
        return nil
    }

    /// 从当前进程签名读 com.apple.security.application-groups。
    /// SPI 不可用/探测失败 → 空列表（只损失重签适配，不影响正常签名）。
    private static func signedAppGroupCandidates() -> [String] {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return [] }
        defer { dlclose(handle) }
        guard let create = dlsym(handle, "SecTaskCreateFromSelf"),
              let copyValue = dlsym(handle, "SecTaskCopyValueForEntitlement") else {
            return []
        }
        typealias CreateFn = @convention(c) (CFAllocator?) -> OpaquePointer?
        typealias CopyFn = @convention(c) (OpaquePointer?, CFString, UnsafeMutablePointer<CFError?>?) -> CFTypeRef?
        let createFn = unsafeBitCast(create, to: CreateFn.self)
        let copyFn = unsafeBitCast(copyValue, to: CopyFn.self)
        guard let task = createFn(nil) else { return [] }
        guard let value = copyFn(
            task,
            "com.apple.security.application-groups" as CFString,
            nil
        ) else {
            return []
        }
        if let list = value as? [String] {
            return list
        }
        return []
    }
}
