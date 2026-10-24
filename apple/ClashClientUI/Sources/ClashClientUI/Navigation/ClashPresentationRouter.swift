#if os(macOS)
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashPushAuthority {
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func canPush(
        hostContext: ClashNavigationHostContext,
        depth: Int?
    ) -> Bool {
        switch hostContext {
        case .standalone, .modal:
            return true
        case .regularDetail:
            return (depth ?? 0) == 0
        }
    }
}

extension ClashPushAuthority {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func trace(
        _ site: String,
        _ hostContext: ClashNavigationHostContext,
        _ depth: Int?
    ) {
        guard ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1"
        else { return }
        let verdict = canPush(hostContext: hostContext, depth: depth)
        FileHandle.standardError.write(
            "[nav] \(site) host=\(hostContext) depth=\(depth.map(String.init) ?? "nil") canPush=\(verdict)\n"
                .data(using: .utf8)!
        )
    }
}

 
 
 
 
 
public enum ClashPushAuthorityProbe {
    public static func trace(_ site: String, mayPush: Bool, hasPusher: Bool) {
        guard ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1"
        else { return }
        FileHandle.standardError.write(
            "[nav] \(site) mayPush=\(mayPush) hasPusher=\(hasPusher)\n"
                .data(using: .utf8)!
        )
    }
}

public extension EnvironmentValues {
     
     
     
     
     
     
     
     
     
     
     
     
    var clashDoorMayPush: Bool {
        ClashPushAuthority.canPush(
            hostContext: clashNavigationHostContext,
            depth: clashNavigationDepth
        )
    }
}
#endif
