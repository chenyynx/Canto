import Foundation
import SwiftUI

@main
struct ClashTVApp: App {
    @UIApplicationDelegateAdaptor(ClashTVAppDelegate.self) private var appDelegate

    private let launchOverrides = ClashTVLaunchOverrides(environment: [:])


    var body: some Scene {
        WindowGroup {
            ClashTVLaunchRoot(overrides: launchOverrides)
        }
    }
}

 
 
 
final class ClashTVAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ClashTVAutoUpdate.register { await ClashTVAutoUpdate.refreshInBackground() }
        return true
    }
}

private struct ClashTVLaunchRoot: View {
    let overrides: ClashTVLaunchOverrides

    @ViewBuilder
    var body: some View {
        if overrides.contentSize == .accessibilityExtraLarge {
            shell.environment(\.sizeCategory, .accessibilityExtraLarge)
        } else {
            shell
        }
    }

    private var shell: some View {
        ClashTVShell(stage: overrides.stage, connectsOnLaunch: overrides.connectsOnLaunch, updatesOnLaunch: overrides.updatesOnLaunch, matrix: overrides)
            .preferredColorScheme(overrides.appearance?.colorScheme)
    }
}
