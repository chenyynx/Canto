import Foundation
import SwiftUI

 
 
 
 
 
 
 
 
enum ClashBackupDataScope: Equatable {
     
    case ordinary
     
    case review(URL)
     
     
    case reviewUnavailable
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum BackupSandbox {
     
     
     
    static func workingDirectory(
        scope: ClashBackupDataScope,
        appGroupContainer: URL?
    ) -> URL? {
        switch scope {
        case .ordinary:
            return appGroupContainer?.appendingPathComponent("working")
        case .review(let container):
            return container.appendingPathComponent("working")
        case .reviewUnavailable:
            return nil
        }
    }

     
     
     
     
     
    static func usesFixtureICloud(
        scope: ClashBackupDataScope,
        uiTestingEnabled: Bool
    ) -> Bool {
        switch scope {
        case .ordinary:
            return uiTestingEnabled
        case .review, .reviewUnavailable:
            return true
        }
    }
}

 
 
 
struct ClashBackupDataScopeKey: EnvironmentKey {
    static let defaultValue: ClashBackupDataScope = .ordinary
}

extension EnvironmentValues {
    var clashBackupDataScope: ClashBackupDataScope {
        get { self[ClashBackupDataScopeKey.self] }
        set { self[ClashBackupDataScopeKey.self] = newValue }
    }
}
