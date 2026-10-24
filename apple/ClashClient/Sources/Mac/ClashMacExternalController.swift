import Clash
import ClashClientUI
import Foundation
import NetworkExtension

extension ExternalControllerCore {
     
     
     
    @MainActor
    static func mac(vpn: VPNController, profiles: ProfilesViewModel) -> Self {
        Self(
            applyInApp: { ClashApplyRemoteControl($0) },
            generateCertificate: { ClashGenerateControllerCertificate() },
            askTunnel: { [weak vpn] in
                guard let session = vpn?.session else { return nil }
                 
                 
                for _ in 0..<60 where session.status == .connecting || session.status == .reasserting {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                guard session.status == .connected,
                      let reply = await ClashClient(session: session).send(["cmd": "remoteControl"]) else { return nil }
                return String(data: reply, encoding: .utf8)
            },
            configurationSays: { [weak profiles] in
                guard let profiles,
                      let active = profiles.profiles.first(where: { $0.id == profiles.activeProfileID }),
                      let yaml = profiles.sourceYAML(for: active) else { return nil }
                return configurationSays(in: yaml)
            }
        )
    }
}
