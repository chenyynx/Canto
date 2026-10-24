import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
struct ProfileRuntimeTrustEditor: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    let profile: Profile
    let baselinePatchJSON: String
    let commit: (String) -> Void

     
     
     
     
     
     
     
    @State private var openedWith: ProfileRuntimeTrustDraft?
    @State private var dismiss = ClashDismissHandle()
    @State private var draft: ProfileRuntimeTrustDraft
    @State private var error = ""
    @State private var addingCertificate = false
     
    @State private var certificateRows = ClashIdentifiedRows()

     
     
     
     
    init(
        profile: Profile,
        draft: ProfileRuntimeTrustDraft? = nil,
        patchJSON: String,
        commit: @escaping (String) -> Void
    ) {
        self.profile = profile
        baselinePatchJSON = patchJSON
        self.commit = commit
        _draft = State(initialValue: draft ?? ProfileRuntimeTrustDraft.editing(profile, patchJSON: patchJSON, sourceYAML: nil))
    }

     
     
     
    static func opening(
        profile: Profile,
        sourceYAML: String?,
        patchJSON: String,
        commit: @escaping (String) -> Void
    ) -> some View {
        ProfileEditorDraftLoader(identifier: "profile-runtime-trust.loading") {
            ProfileRuntimeTrustDraft.editing(profile, patchJSON: patchJSON, sourceYAML: sourceYAML)
        } content: { draft in
            ProfileRuntimeTrustEditor(profile: profile, draft: draft, patchJSON: patchJSON, commit: commit)
        }
    }

    var body: some View {
        Form {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            Section {
                ClashSettingsToggleRow(
                    Text("Override Trusted Certificates"),
                    isOn: certificatesEnabled
                )
                    .accessibilityIdentifier("profile-runtime-trust.certificates.enabled")

                if let certificates = draft.customTrustCertificates {
                     
                     
                     
                     
                    ForEach(certificateRows.current(for: certificates)) { row in
                        let index = row.index
                        let value = certificateRows.index(of: row.id)
                            .map { certificates[$0] } ?? ""
                        HStack {
                            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                                Text("Certificate \(index + 1)")
                                Text("Public PEM · \(Self.byteCount(value))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
                        .accessibilityIdentifier("profile-runtime-trust.certificate.\(index)")
                         
                         
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                guard var kept = draft.customTrustCertificates
                                else { return }
                                certificateRows.remove(row.id, from: &kept)
                                draft.customTrustCertificates = kept
                            } label: {
                                Label("Delete", systemImage: ClashSymbol.trash.name)
                            }
                            .tint(.red)
                            .accessibilityLabel("Remove Certificate \(index + 1)")
                        }
                    }
                    .onAppear {
                        certificateRows.resync(count: certificates.count)
                    }
                    .onChange(of: certificates.count) {
                        certificateRows.resync(count: $0)
                    }

                     
                     
                     
                    ClashConfigurationLibraryAddCard(
                        kind: .certificates,
                        palette: ClashClientUI.ClashProductPalette.clashProduct,
                        nativeList: true,
                        showsHeader: false
                    ) {
                        addingCertificate = true
                    }
                    .accessibilityIdentifier("profile-runtime-trust.certificate.add")
                }
            } header: {
                Text("Custom Trust")
            }

            Section {
                HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
                    ClashIconWell(symbol: .lockShield, tint: .gray)
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        Text("Certificate and Private Key")
                            .font(.headline)
                        Text(clash: .copy(serverTLSMessage))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, ClashTheme.Spacing.tight)
                .accessibilityIdentifier("profile-runtime-trust.server-tls")
            } header: {
                Text("External Controller TLS")
            }

            if !error.isEmpty {
                Section {
                    ClashStatusMessage(text: .copy(error), kind: .error)
                }
            }
        }
         
        .clashRegistersDeparture(
            isDirty: hasChanges,
            save: { completion in
                completion(writeDraft())
            },
            discard: { if let openedWith { draft = openedWith } }
        )
        .onAppear { if openedWith == nil { openedWith = draft } }
        .clashPageTitle("Compatibility & Trust")
        .clashDetailPageInsets()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if !insideProductModal {
                    Button("Done", action: persist)
                        .accessibilityIdentifier("profile-runtime-trust.done")
                }
            }
        }
        .clashProductModal(isPresented: $addingCertificate, role: .form) {
            CertificateAddSheet(close: { addingCertificate = false }) { certificate in
                add(certificate)
                addingCertificate = false
            }
            .clashModalPresentation(.form)
        }
        .accessibilityIdentifier("profile-runtime-trust.screen")
        .clashCapturesDismiss(dismiss)
         
         
         
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                     
                     
                     
                     
                     
                     
                     
                ClashModalActionBar(primaryTitle: "Done",
                    primaryDisabled: !hasChanges,
                    onPrimary: persist)
            }
        }
    }

    private var certificatesEnabled: Binding<Bool> {
        Binding(
            get: { draft.customTrustCertificates != nil },
            set: { enabled in
                draft.customTrustCertificates = enabled
                    ? (draft.customTrustCertificates ?? []) : nil
            }
        )
    }

    private var serverTLSMessage: String {
        draft.hasUnsupportedServerTLSFields
            ? "External controller TLS material is present. Clash keeps it and uses it when the controller is served over HTTPS."
            : "This profile sets no external controller TLS material."
    }

     
     
     
     
     
     
     
    private var hasChanges: Bool {
        var working = profile
        working.override.patchJSON = baselinePatchJSON
        guard let updated = try? draft.applying(to: working) else { return true }
        return updated.override.patchJSON != baselinePatchJSON
    }

     
     
     
     
     
    private func persist() { if writeDraft() { dismiss() } }

    @discardableResult
    private func writeDraft() -> Bool {
        do {
            var working = profile
            working.override.patchJSON = baselinePatchJSON
            let updated = try draft.applying(to: working)
            commit(updated.override.patchJSON)
            return true
        } catch let bounded as ProfileRuntimeTrustError {
            error = bounded.localizedDescription
        } catch {
            self.error = "Runtime and trust settings could not be prepared. The previous configuration remains unchanged."
        }
        return false
    }

    private func add(_ certificate: String) {
        if draft.customTrustCertificates == nil { draft.customTrustCertificates = [] }
        if draft.customTrustCertificates?.contains(certificate) == false {
            draft.customTrustCertificates?.append(certificate)
        }
        error = ""
    }

    private static func byteCount(_ value: String) -> String {
        let bytes = value.utf8.count
        return bytes < 1_024 ? "\(bytes) B" : "\((bytes + 1_023) / 1_024) KB"
    }
}

 
 
 
struct CertificateAddSheet: View {
    @Environment(\.locale) private var locale
    let close: () -> Void
    let added: (String) -> Void

    @State private var tab = 1
    @State private var address = ""
    @State private var pemText = ""
    @State private var importing = false
    @State private var failure = ""
    @State private var showsFailure = false
    @State private var showsFileImporter = false

    static func certificate(from raw: String) throws -> String {
        try ProfileRuntimeTrustDraft.normalizedCertificate(raw)
    }

    var body: some View {
        ClashFeatureNavigationContainer {
             
             
             
             
             
            Form { fields }
            .clashPinnedTopBar { tabs }
            .clashPageTitle("Add Certificate")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                        .accessibilityIdentifier("trust.add.cancel")
                }
                ToolbarItem(placement: .confirmationAction) { commitButton }
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.x509Certificate, .data, .plainText, .text],
            allowsMultipleSelection: false
        ) { outcome in
            importFile(outcome)
        }
        .alert("Import Failed", isPresented: $showsFailure) {
            Button("OK") {}
        } message: {
            Text(verbatim: failure)
        }
    }

    private var tabs: some View {
        Picker("Add Certificate", selection: $tab) {
            Text(ClashCopy.key("URL")).tag(1)
            Text(ClashCopy.key("File")).tag(2)
            Text(ClashCopy.key("Manual")).tag(3)
        }
        .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 8)
        .accessibilityIdentifier("trust.add.tabs")
    }

    @ViewBuilder
    private var fields: some View {
        switch tab {
        case 1:
            Section {
                TextField("Certificate URL", text: $address)
                    .textContentType(.URL)
#if !os(macOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("trust.add.link.address")
            }
        case 2:
            Section {
                Button("Choose File…") { showsFileImporter = true }
                    .accessibilityIdentifier("trust.add.file.choose")
            }
        default:
            Section {
                TextEditor(text: $pemText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 240)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("trust.add.pem")
            }
        }
    }

    @ViewBuilder
    private var commitButton: some View {
        if tab == 1 {
            Button(importing ? "Importing…" : "Import") {
                Task { @MainActor in await importLink() }
            }
            .disabled(importing || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("trust.add.link.import")
        } else if tab == 3 {
             
             
            Button("Add") { finish(pemText) }
                .disabled(pemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("trust.add.save")
        }
    }

    private func importLink() async {
        importing = true
        defer { importing = false }
        do {
            finish(try await ScriptImport.body(at: address))
        } catch {
            fail(ClashErrorCopy.message(error, locale: locale))
        }
    }

    private func importFile(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case let .success(urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                fail(ClashErrorCopy.message(ProfileRuntimeTrustError.invalidCertificate, locale: locale))
                return
            }
            finish(text)
        case let .failure(error):
            fail(ClashErrorCopy.message(error, locale: locale))
        }
    }

    private func finish(_ raw: String) {
        do {
            added(try Self.certificate(from: raw))
        } catch {
            fail(ClashErrorCopy.message(error, locale: locale))
        }
    }

    private func fail(_ message: String) {
        failure = message
        showsFailure = true
    }
}

 
 
 
 
struct ProfileTrustPage: View {
    @Environment(\.locale) private var locale
    let profile: Profile
    let sourceYAML: String?
    let patchJSON: String
    let save: (String) async throws -> Void

    @State private var dismiss = ClashDismissHandle()
    @State private var error = ""

    var body: some View {
        ClashFeatureNavigationContainer {
            ProfileRuntimeTrustEditor.opening(
                profile: profile,
                sourceYAML: sourceYAML,
                patchJSON: patchJSON
            ) { patchJSON in
                Task {
                    do {
                        try await save(patchJSON)
                        close()
                    } catch {
                        self.error = ClashErrorCopy.message(error, locale: locale)
                    }
                }
            }
            .clashFeaturePresentation(ownsNavigationContainer: true)
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                }
            }
            .alert("Cannot Save", isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) {
                Button("OK") {}
            } message: {
                Text(verbatim: error)
            }
        }
        .clashCapturesDismiss(dismiss)
    }

    private func close() {
        dismiss.closeModalOrDismiss()
    }
}
