import Foundation

#if canImport(Security) && (os(iOS) || os(macOS) || os(tvOS))

// iCloud entitlement 运行时探测。
//
// 背景（2026-10-14 崩溃修复）：sideloaded 包（全能签/企业签等重签名安装）的描述文件
// 永远不含 iCloud 容器 entitlement——CKContainer(identifier:) 在无该权限的进程里
// 构造时 CloudKit 框架直接抛 NSException（未捕获 → SIGABRT 闪退，日志
// lastExceptionBacktrace: CKSDKVersion → CKContainer.__allocating_init）。
// Xcode 正常签名（带 iCloud 能力）不受影响，因此上游从未暴露。
//
// 方案：构造 CKContainer 前先探测当前进程签名里的
// com.apple.developer.icloud-container-identifiers；缺失则不触碰 CloudKit，
// 走既有的 unavailable 错误路径（UI 显示 iCloud 不可用，不崩）。
//
// SecTask API 是私有 SPI（LiveContainer/Provenance 等项目同款用法），
// 经 dlsym 动态解析，避免头文件/链接依赖。
// public：主 App 的 ConfigUI/ICloudAutoBackup.swift 跨模块使用。
public enum ICloudEntitlementProbe {
    static let entitlementKey = "com.apple.developer.icloud-container-identifiers"

    /// 当前进程签名是否含 iCloud 容器 entitlement。
    /// 探测失败（API 不可用等）按"有"处理——宁可放行给 CloudKit 自己报错，
    /// 也不因探测误判把正常签名环境挡掉（探测只会在这条崩溃链上更保守）。
    public static var hasICloudEntitlement: Bool {
        cached ?? true
    }

    private static let cached: Bool? = probe()

    private static func probe() -> Bool? {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let create = dlsym(handle, "SecTaskCreateFromSelf"),
              let copyValue = dlsym(handle, "SecTaskCopyValueForEntitlement") else {
            return nil
        }
        typealias CreateFn = @convention(c) (CFAllocator?) -> OpaquePointer?
        typealias CopyFn = @convention(c) (OpaquePointer?, CFString, UnsafeMutablePointer<CFError?>?) -> CFTypeRef?
        let createFn = unsafeBitCast(create, to: CreateFn.self)
        let copyFn = unsafeBitCast(copyValue, to: CopyFn.self)
        guard let task = createFn(nil) else { return nil }
        guard let value = copyFn(task, entitlementKey as CFString, nil) else {
            // 签名里没有该 entitlement → 明确无 iCloud 权限
            return false
        }
        // entitlement 存在且为非空字符串数组即认为可用
        if let list = value as? [String] {
            return !list.isEmpty
        }
        return true
    }
}

#endif
