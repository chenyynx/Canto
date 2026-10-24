import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum LocalNetworkPermission {
     
     
     
    static let defaultsKey = "core.allow-lan-permitted"

     
     
     
     
    static func isPermitted(_ defaults: UserDefaults?) -> Bool {
        guard let defaults, defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    static func setPermitted(_ permitted: Bool, in defaults: UserDefaults?) {
        defaults?.set(permitted, forKey: defaultsKey)
    }

     
    static let mirrorClearedKey = "core.allow-lan-permitted.mirror-cleared-d385"

     
     
     
     
     
     
     
    static func clearPublicationMirror(in defaults: UserDefaults?) {
        guard let defaults, !defaults.bool(forKey: mirrorClearedKey) else { return }
        defaults.removeObject(forKey: defaultsKey)
        defaults.set(true, forKey: mirrorClearedKey)
    }
}
