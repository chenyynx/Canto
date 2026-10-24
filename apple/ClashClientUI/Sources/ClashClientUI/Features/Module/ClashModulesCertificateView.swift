import ClashClientKit
import SwiftUI

 
 
 
 
 
 
 
 
 
public struct ClashModulesCertificateView: View {
    @ObservedObject private var feed: ClashModulesCertificateFeed
    private let perform: (ClashModulesAction) -> Void
    @State private var confirmsNewCertificate = false

     
    init(feed: ClashModulesCertificateFeed, perform: @escaping (ClashModulesAction) -> Void) {
        self.feed = feed
        self.perform = perform
    }

     
    public init(snapshot: ClashModulesSnapshot, perform: @escaping (ClashModulesAction) -> Void) {
        self.init(feed: ClashModulesCertificateFeed(snapshot), perform: perform)
    }

    public var body: some View {
        Form {
            if let certificate = feed.certificate {
                Section {
                    stateRow(certificate.state)
                    ForEach(Array(certificate.steps.enumerated()), id: \.offset) { _, step in
                        Text(clash: step)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note = certificate.note {
                         
                         
                        Text(clash: note)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("modules.certificate.note")
                    }
                    if certificate.state != .ready, let action = certificate.action {
                        actionButton(action)
                    }
                }
                 
                if certificate.state == .ready, let action = certificate.action {
                    Section {
                        actionButton(action)
                    }
                }
            }
        }
        .modifier(ClashModulesFormStyle())
        .clashPageTitle("Certificate")
        .accessibilityIdentifier("modules.certificate.page")
    }

    private func stateRow(_ state: ClashModulesSnapshot.CertificateState) -> some View {
        Label {
            Text(clash: state.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: state == .ready
                  ? ClashSymbol.checkmarkShieldFill.rawValue
                  : ClashSymbol.exclamationmarkShieldFill.rawValue)
                .foregroundStyle(state == .ready ? Color.green : Color.orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("modules.certificate.state")
    }

    private func actionButton(_ action: ClashModulesSnapshot.CertificateAction) -> some View {
        Button {
            switch action.kind {
            case .makeNew: confirmsNewCertificate = true
            default: perform(.certificate(action.kind))
            }
        } label: {
            Text(clash: action.title)
        }
        .disabled(feed.isBusy)
        .accessibilityIdentifier("modules.certificate.action.\(Self.actionName(action.kind))")
         
         
         
        .confirmationDialog(
             
             
            Text("Make a New Module Certificate?"),
            isPresented: $confirmsNewCertificate,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                perform(.renewCertificate)
            } label: {
                Text("Make a New Certificate")
            }
            .accessibilityIdentifier("modules.certificate.renew.confirm")
            Button(role: .cancel) {} label: {
                Text("Cancel")
            }
        } message: {
            if let warning = feed.certificate?.renewWarning {
                Text(clash: warning)
            }
        }
    }

     
     
     
    nonisolated static func actionName(_ kind: ClashModulesSnapshot.CertificateActionKind) -> String {
        switch kind {
        case .create: #"create"#
        case .installProfile: #"installProfile"#
        case .installAndTrust: #"installAndTrust"#
        case .openInKeychainAccess: #"openInKeychainAccess"#
        case .makeNew: #"makeNew"#
        }
    }
}

 
 
 
 
@MainActor
final class ClashModulesCertificateFeed: ObservableObject {
    @Published private(set) var certificate: ClashModulesSnapshot.Certificate?
    @Published private(set) var isBusy: Bool

    init(_ snapshot: ClashModulesSnapshot) {
        certificate = snapshot.certificate
        isBusy = snapshot.isBusy
    }

    func take(_ snapshot: ClashModulesSnapshot) {
        if certificate != snapshot.certificate { certificate = snapshot.certificate }
        if isBusy != snapshot.isBusy { isBusy = snapshot.isBusy }
    }
}
