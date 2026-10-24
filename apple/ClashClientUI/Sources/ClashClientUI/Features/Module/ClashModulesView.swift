import ClashClientKit
import SwiftUI

 
 
 
 
 
 
 
 
 
 
public struct ClashModulesView<AddModule: View>: View {
    private let snapshot: ClashModulesSnapshot
    private let perform: (ClashModulesAction) -> Void
    private let detail: (String) -> ClashModuleDetailSnapshot?
    private let addModule: (_ dismiss: @escaping () -> Void) -> AddModule
     
     
    private let opensAddModule: Bool

    @State private var showsAddModule = false
    @State private var openedModule: ClashModulesOpenedModule?
     
     
    @StateObject private var certificateFeed: ClashModulesCertificateFeed
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        snapshot: ClashModulesSnapshot,
        perform: @escaping (ClashModulesAction) -> Void,
        detail: @escaping (String) -> ClashModuleDetailSnapshot?,
        opensAddModule: Bool = false,
        @ViewBuilder addModule: @escaping (_ dismiss: @escaping () -> Void) -> AddModule
    ) {
        self.snapshot = snapshot
        self.perform = perform
        self.detail = detail
        self.opensAddModule = opensAddModule
        self.addModule = addModule
        _certificateFeed = StateObject(wrappedValue: ClashModulesCertificateFeed(snapshot))
    }

    public var body: some View {
        Form {
            decryptionSection
             
             
             
            if !snapshot.notices.isEmpty {
                noticesSection
            }
            modulesSection
        }
        .modifier(ClashModulesFormStyle())
        .clashPageTitle("Modules")
        .onChange(of: snapshot) { certificateFeed.take($0) }
        .onAppear { if opensAddModule { showsAddModule = true } }
        .onChange(of: opensAddModule) { opens in
            if opens { showsAddModule = true }
        }
        .sheet(item: $openedModule) { opened in
             
             
            ClashModuleDetailView(snapshot: detail(opened.id), editor: snapshot.editor, perform: perform) {
                openedModule = nil
            }
            .clashModalPresentation(Self.detailPresentation)
        }
        .sheet(isPresented: $showsAddModule) {
            addModule { showsAddModule = false }
                .clashModalPresentation(.form)
        }
        .modifier(ClashModulesEditorPresentation(editor: newModuleEditor, perform: perform))
        .accessibilityIdentifier("modules.page")
    }

     
     
    static var detailPresentation: ClashModalPresentationRole {
#if os(macOS)
        .fitted
#else
        .page
#endif
    }

     
     
    private var newModuleEditor: ClashModuleEditorSnapshot? {
        snapshot.editor.flatMap { $0.moduleID == nil ? $0 : nil }
    }

     

     
     
     
     
     
     
    private var decryptionSection: some View {
        Section {
            Toggle(isOn: Binding(get: { snapshot.isOn }, set: { perform(.setEnabled($0)) })) {
                Text("HTTPS Decryption")
            }
            .modifier(ClashModulesSwitchStyle())
            .disabled(snapshot.isBusy)
            .accessibilityIdentifier("modules.switch")
            if let certificate = snapshot.certificate {
                ClashRoutedViewLink {
                    ClashModulesCertificateView(feed: certificateFeed, perform: perform)
                        .clashPushedDetailPage()
                } label: {
                    HStack(spacing: ClashTheme.Spacing.row) {
                        Text("Certificate")
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        Text(clash: certificate.state.rowValue)
                            .foregroundStyle(certificate.state == .ready ? Color.secondary : Color.orange)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .accessibilityIdentifier("modules.certificate")
            }
            if let install = snapshot.install {
                Button {
                    perform(.certificate(install.action.kind))
                } label: {
                    Text(clash: install.action.title)
                }
                .disabled(snapshot.isBusy)
                .accessibilityIdentifier("modules.install.\(ClashModulesCertificateView.actionName(install.action.kind))")
            }
        } footer: {
            if let install = snapshot.install {
                Text(clash: install.effect)
            } else if !snapshot.isOn {
                Text("When it's off, only the rules in your modules are used.")
            }
        }
    }

    private var noticesSection: some View {
        Section {
            ForEach(snapshot.notices) { notice in
                Label {
                    Text(clash: notice.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                        .foregroundStyle(Color.orange)
                }
                .accessibilityIdentifier("modules.notice.\(notice.id)")
                if let action = notice.action {
                    Button {
                        perform(.notice(action))
                    } label: {
                        Text(clash: notice.actionTitle ?? "Try Again")
                    }
                    .accessibilityIdentifier("modules.notice.action.\(notice.id)")
                }
            }
        }
    }

    private var modulesSection: some View {
         
        let paths = ClashModulesSnapshot.ModuleRow.distinguishingPaths(snapshot.modules)
        return Section {
            ForEach(snapshot.modules) { row in
                moduleRow(row, path: paths[row.id])
            }
            ClashAddRow(Text("Add Module")) {
                showsAddModule = true
            }
            .disabled(snapshot.isBusy)
            .accessibilityIdentifier("modules.modules.add")
             
             
            ClashAddRow(Text("New Module"), symbol: .docBadgePlus, action: { perform(.newModule) }) {
                ClashModulesNewModuleLabel()
            }
            .disabled(snapshot.isBusy)
            .accessibilityIdentifier("modules.modules.new")
        } header: {
            Text("Modules")
        }
    }

     
     
     
    @ViewBuilder
    private func moduleRow(_ row: ClashModulesSnapshot.ModuleRow, path: String?) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.row) {
                    moduleLines(row, path: path)
                    HStack(spacing: ClashTheme.Spacing.row) {
                        moduleSwitch(row)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        moduleInfoButton(row)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: ClashTheme.Spacing.row) {
                    moduleLines(row, path: path)
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    moduleInfoButton(row)
                    moduleSwitch(row)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                perform(.removeModule(id: row.id))
            } label: {
                Text("Delete")
            }
        }
        .modifier(ClashModulesDeleteSwipe { perform(.removeModule(id: row.id)) })
    }

     
     
    private func moduleLines(_ row: ClashModulesSnapshot.ModuleRow, path: String?) -> some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            Text(verbatim: row.name)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if let path {
                Text(unhyphenated: path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .truncationMode(.middle)
            }
            if dynamicTypeSize.isAccessibilitySize {
                 
                if let source = Self.sourceName(row, locale: locale) {
                    Text(unhyphenated: source)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let updated = Self.updatedLine(row, locale: locale) {
                    Text(verbatim: updated)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                sourceLines(row)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: Self.entriesLine(row, locale: locale))
                .font(.footnote)
                .foregroundStyle(.secondary)
             
            if row.failure != nil {
                Text("Update failed")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

     
     
     
     
    @ViewBuilder
    private func sourceLines(_ row: ClashModulesSnapshot.ModuleRow) -> some View {
        let updated = Self.updatedLine(row, locale: locale)
        if let source = Self.sourceName(row, locale: locale) {
            if let updated {
                if #available(iOS 16.0, *) {
                    ViewThatFits(in: .horizontal) {
                        Text(unhyphenated: source + " · " + updated)
                            .lineLimit(1)
                        stackedSourceLines(source, updated)
                    }
                } else {
                    stackedSourceLines(source, updated)
                }
            } else {
                Text(unhyphenated: source)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        } else if let updated {
             
            Text(verbatim: updated)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stackedSourceLines(_ source: String, _ updated: String) -> some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            Text(unhyphenated: source)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(verbatim: updated)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func moduleInfoButton(_ row: ClashModulesSnapshot.ModuleRow) -> some View {
        Button {
            openedModule = ClashModulesOpenedModule(id: row.id)
        } label: {
            Image(systemName: ClashSymbol.infoCircle.rawValue)
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Details"))
        .accessibilityIdentifier("modules.module.info.\(row.id)")
    }

    private func moduleSwitch(_ row: ClashModulesSnapshot.ModuleRow) -> some View {
        Toggle(isOn: Binding(get: { row.enabled }, set: { perform(.setModule(id: row.id, enabled: $0)) })) {
            Text(verbatim: row.name)
        }
        .modifier(ClashModulesSwitchStyle())
        .labelsHidden()
        .disabled(snapshot.isBusy)
        .accessibilityIdentifier("modules.module.toggle.\(row.id)")
    }

     

     
     
     
    nonisolated static func sourceLine(_ row: ClashModulesSnapshot.ModuleRow, locale: Locale, now: Date = Date()) -> String {
        [sourceName(row, locale: locale), updatedLine(row, locale: locale, now: now)].compactMap { $0 }.joined(separator: " · ")
    }

     
     
    nonisolated static func sourceName(_ row: ClashModulesSnapshot.ModuleRow, locale: Locale) -> String? {
        switch row.source {
        case .link(let host): return host
        case .local: return ClashCopy.string("Local", locale: locale)
        case .unknown: return nil
        }
    }

     
    nonisolated static func updatedLine(_ row: ClashModulesSnapshot.ModuleRow, locale: Locale, now: Date = Date()) -> String? {
        guard let updated = row.updatedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
         
         
        let when = formatter.localizedString(for: min(updated, now.addingTimeInterval(-1)), relativeTo: now)
        return ClashCopy.string(for: .format("Last updated %@", [when]), locale: locale)
    }

     
     
     
     
    nonisolated static func entriesLine(_ row: ClashModulesSnapshot.ModuleRow, locale: Locale) -> String {
         
        let waiting = row.enabled ? row.waitingCount : 0
        return ClashModuleCountLine.string(
            ClashModuleCountLine.parts(kept: row.effectiveCount + waiting, waiting: waiting, waitsFor: row.waitsFor,
                                       enabled: row.enabled, details: false, locale: locale),
            locale: locale)
    }
}

 
 
 
 
 
struct ClashModulesNewModuleLabel: View {
    var body: some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            Image(systemName: ClashSymbol.plusCircleFill.rawValue)
                .font(.title3)
                .hidden()
                .overlay(
                    Image(systemName: ClashSymbol.docBadgePlus.rawValue)
                        .font(.title3)
                )
                .accessibilityHidden(true)
            Text("New Module")
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tint)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

 
 
struct ClashModulesEditorPresentation: ViewModifier {
    let editor: ClashModuleEditorSnapshot?
    let perform: (ClashModulesAction) -> Void

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.sheet(item: Binding(get: { editor }, set: { if $0 == nil { perform(.closeEditor) } })) { opened in
            ClashModuleEditorView(editor: editor ?? opened, perform: perform)
                .clashModalPresentation(.page)
        }
#endif
    }
}

struct ClashModulesOpenedModule: Identifiable, Equatable {
    let id: String
}

 
 
 
struct ClashModulesSwitchStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.toggleStyle(.switch)
#endif
    }
}

 
 
 
 
 
struct ClashModulesFormStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content.formStyle(.grouped).modifier(ClashMacHardTopEdge())
#else
        content
#endif
    }
}

 
struct ClashModulesDeleteSwipe: ViewModifier {
    let delete: () -> Void

    func body(content: Content) -> some View {
#if os(iOS)
        content.swipeActions(edge: .trailing) {
            Button(role: .destructive, action: delete) {
                Text("Delete")
            }
            .accessibilityIdentifier("modules.module.delete")
        }
#else
        content
#endif
    }
}
