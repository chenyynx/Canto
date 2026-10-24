import Clash
import ClashClientUI
import SwiftUI

struct STUNTestView: View {
    @ObservedObject var model: STUNTestModel

    var body: some View {
        ClashMacSettingsFormContainer {
            Section {
                if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                     
                     
                     
                    TextField(
                        text: $model.server,
                        prompt: Text(verbatim: "stun.example.org:3478")
                    ) {
                        Text("Server")
                    }
                        .accessibilityIdentifier("stun.server")
                    .disabled(model.isRunning)
                } else {
                TextField("Server", text: $model.server)
                    .accessibilityIdentifier("stun.server.compact")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(model.isRunning)
                }

                Picker("Outbound", selection: $model.selectedOutbound) {
                    ForEach(model.outboundOptions) { option in
                        Text(clash: .copy(option.title)).tag(option.name)
                    }
                }
                    .accessibilityIdentifier("stun.outbound")
                .disabled(model.isRunning)
            } header: {
                Text("Configuration")
            } footer: {
                Text("Follow Rules uses the active routing mode and rules. Selecting an outbound tests that exact UDP-capable proxy or group. Results describe UDP egress for diagnostics only and never change routing.")
            }

            Section("Action") {
                 
                 
                if model.isRunning {
                    Button(role: .destructive) { model.cancel() } label: {
                        Text("Cancel Test")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .clashSecondaryActionButtonStyle()
                    .clashCapsuleButtonBorderShape()
                    .controlSize(.regular)
                    .accessibilityIdentifier("stun.cancel")
                } else {
                    Button { model.start() } label: {
                        Text("Start Test")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .clashPrimaryActionButtonStyle()
                    .clashCapsuleButtonBorderShape()
                    .controlSize(.regular)
                    .accessibilityIdentifier("stun.start")
                }
            }

            if model.phase >= 0 || !model.lastError.isEmpty {
                Section("Results") {
                    if !model.lastError.isEmpty {
                        ClashStatusMessage(text: .verbatim(model.lastError), kind: .error)
                    }
                    STUNResultRow(
                        title: "External address",
                        value: model.externalAddress.isEmpty ? "—" : model.externalAddress,
                        active: model.isRunning && model.phase == ClashSTUNPhaseBinding
                    )
                    .accessibilityIdentifier("stun.result.externalAddress")
                    STUNResultRow(
                        title: "Address family",
                        value: model.externalAddressFamily == ClashSTUNAddressFamilyUnknown
                            ? "—" : ClashFormatSTUNAddressFamily(model.externalAddressFamily),
                        active: false
                    )
                    STUNResultRow(
                        title: "Latency",
                        value: model.externalAddress.isEmpty ? "—" : "\(model.latencyMilliseconds) ms",
                        active: model.isRunning && model.phase == ClashSTUNPhaseBinding
                    )
                    if model.phase == ClashSTUNPhaseDone && !model.natTypeSupported {
                        STUNResultRow(
                            title: "NAT type detection",
                            value: "Unsupported by server",
                            active: false
                        )
                    } else {
                        STUNResultRow(
                            title: "NAT mapping",
                            value: model.natMapping == ClashNATMappingUnknown
                                ? "—" : ClashFormatNATMapping(model.natMapping),
                            active: model.isRunning && model.phase == ClashSTUNPhaseNATMapping
                        )
                        STUNResultRow(
                            title: "NAT filtering",
                            value: model.natFiltering == ClashNATFilteringUnknown
                                ? "—" : ClashFormatNATFiltering(model.natFiltering),
                            active: model.isRunning && model.phase == ClashSTUNPhaseNATFiltering
                        )
                    }
                }
            }
        }
        
        .clashPageTitle("STUN Test")
        .task { await model.refreshOutbounds() }
        .onDisappear {
            if model.isRunning { model.cancel() }
        }
    }
}

private struct STUNResultRow: View {
    let title: String
    let value: String
    let active: Bool

    var body: some View {
        HStack {
            Text(clash: .copy(title))
            Spacer()
            if active { ProgressView().controlSize(.small) }
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}


