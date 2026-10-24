import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashMacAppGroupAccess {
     
     
     
     
     
     
    static func readableContainer() -> URL? {


        guard let container = ClashAppIdentifiers.appGroupContainer else {
            return nil
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: container.path,
            isDirectory: &isDirectory
        )
        guard exists, isDirectory.boolValue else { return nil }
        guard FileManager.default.isReadableFile(atPath: container.path) else {
            return nil
        }
        return container
    }

     
     
     
    static var isWithheldFromThisProcess: Bool {

        false

    }

     
     
     
     
     
     
     
     
     
     
     
    @MainActor
    static func awaitReadable(
        read: () -> URL?,
        pause: (TimeInterval) async -> Bool,
        patience: TimeInterval = 5,
        onImpatient: () -> Void
    ) async -> URL? {
        var waited: TimeInterval = 0
        var saidSo = false
        while true {
            if let container = read() { return container }
            if !saidSo, waited >= patience {
                saidSo = true
                onImpatient()
            }
            let interval: TimeInterval = waited < 10 ? 0.5 : 2
            guard await pause(interval) else { return nil }
            waited += interval
        }
    }
}
