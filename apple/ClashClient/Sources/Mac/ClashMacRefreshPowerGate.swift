import Foundation
import ClashClientUI

 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacRefreshPowerGate {
    private let isLowPower: () -> Bool
    private let scan: () async -> Void
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?
    private var heldSinceLastScan = false
     
     
     
    private var scanning = false

    init(
        center: NotificationCenter = .default,
        isLowPower: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        scan: @escaping () async -> Void
    ) {
        self.center = center
        self.isLowPower = isLowPower
        self.scan = scan
    }

     
     
    func start() {
        guard observer == nil else { return }
        observer = center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.powerStateDidChange() }
        }
    }

    func stop() {
        if let observer { center.removeObserver(observer) }
        observer = nil
    }

     
    @discardableResult
    func automatic() async -> Bool {
        guard !isLowPower() else {
            if !heldSinceLastScan {
                heldSinceLastScan = true
                ClashLogStore.shared.append(
                    "automatic resource refresh held: Low Power Mode is on",
                    stream: .app
                )
            }
            return false
        }
        heldSinceLastScan = false
        guard !scanning else { return false }
        scanning = true
        defer { scanning = false }
        await scan()
        return true
    }

     
     
    func powerStateDidChange() async {
        guard heldSinceLastScan, !isLowPower() else { return }
        await automatic()
    }
}
