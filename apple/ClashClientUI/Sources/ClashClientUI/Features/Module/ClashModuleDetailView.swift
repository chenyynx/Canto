import ClashClientKit
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
public struct ClashModuleDetailView: View {
    private let snapshot: ClashModuleDetailSnapshot?
    private let editor: ClashModuleEditorSnapshot?
    private let perform: (ClashModulesAction) -> Void
    private let close: () -> Void
    @State private var confirmsDelete = false
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(snapshot: ClashModuleDetailSnapshot?, editor: ClashModuleEditorSnapshot? = nil,
                perform: @escaping (ClashModulesAction) -> Void, close: @escaping () -> Void) {
        self.snapshot = snapshot
        self.editor = editor
        self.perform = perform
        self.close = close
    }

     
    private var thisModulesEditor: ClashModuleEditorSnapshot? {
        guard let editor, let id = editor.moduleID, id == snapshot?.id else { return nil }
        return editor
    }

    public var body: some View {
#if os(macOS)
        macSheet
            .modifier(ClashModulesEditorPresentation(editor: thisModulesEditor, perform: perform))
            .accessibilityIdentifier("modules.detail")
#else
        ClashSingleColumnNavigationContainer {
            content
                .clashPageTitle(snapshot.map { ClashDisplayText.verbatim($0.name) } ?? "Module", watchAs: "modules.module")
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) {
                        ClashSheetCloseButton {
                            close()
                        }
                    }
                }
                .clashProductModalRoot(title: snapshot?.name ?? "Module")
        }
        .modifier(ClashModulesEditorPresentation(editor: thisModulesEditor, perform: perform))
        .accessibilityIdentifier("modules.detail")
#endif
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            List {
                headerSection(snapshot)
                 
                 
                ClashModuleInformationSection(snapshot: snapshot)
                 
                 
                if !snapshot.panels.isEmpty {
                    ClashModulePanelsSection(panels: snapshot.panels) { perform(.refreshPanel(id: $0)) }
                }
                if let settings = snapshot.settings {
                    ClashModuleSettingsSection(moduleID: snapshot.id, settings: settings, perform: perform)
                }
                ForEach(snapshot.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            itemRow(item)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
                Section {
                    deleteButton(snapshot, title: "Delete Module")
                }
            }
            .modifier(ClashModulesListStyle())
             
            .task(id: snapshot.id) { perform(.panelsAppeared(module: snapshot.id)) }
        } else {
            List {}
                .modifier(ClashModulesListStyle())
        }
    }

     
     
     
     
     
     
     
    private func deleteButton(_ snapshot: ClashModuleDetailSnapshot, title: ClashDisplayText,
                              destructive: Bool = true) -> some View {
        Button(role: destructive ? .destructive : nil) {
            confirmsDelete = true
        } label: {
            Text(clash: title)
        }
        .accessibilityIdentifier("modules.detail.delete")
        .confirmationDialog(
            Text(clash: .format("Delete %@?", [snapshot.name])),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                perform(.removeModule(id: snapshot.id))
                close()
            } label: {
                Text("Delete Module")
            }
            .accessibilityIdentifier("modules.detail.delete.confirm")
            Button(role: .cancel) {} label: {
                Text("Cancel")
            }
        }
    }

     
     
     
    @ViewBuilder
    private func sectionHeader(_ section: ClashModuleDetailSnapshot.Section) -> some View {
        if dynamicTypeSize.isAccessibilitySize, let note = Self.headerNote(section) {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    Text(clash: section.title)
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    Text(verbatim: ClashCopy.count(section.items.count, locale: locale))
                }
                headerNoteText(note)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(clash: section.title)
                Spacer(minLength: ClashTheme.Spacing.compact)
                if let note = Self.headerNote(section) {
                    headerNoteText(note)
                }
                Text(verbatim: ClashCopy.count(section.items.count, locale: locale))
            }
        }
    }

     
     
     
    private func headerNoteText(_ note: ClashDisplayText) -> some View {
        Text(clash: note)
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func headerSection(_ snapshot: ClashModuleDetailSnapshot) -> some View {
        Section {
            Toggle(isOn: Binding(get: { snapshot.enabled },
                                 set: { perform(.setModule(id: snapshot.id, enabled: $0)) })) {
                Text(verbatim: snapshot.name)
            }
            .modifier(ClashModulesSwitchStyle())
            .accessibilityIdentifier("modules.detail.toggle")
            if let author = snapshot.author {
                valueRow("Author") { authorText(author) }
            }
            if let source = Self.sourceText(snapshot, locale: locale) {
                valueRow("Source") {
                     
                    Text(unhyphenated: source)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let updated = snapshot.updatedAt {
                valueRow(Self.timeTitle(snapshot)) {
                    Text(updated, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                }
            }
            Text(verbatim: countsText(snapshot))
                .font(.subheadline)
             
            if let failure = snapshot.failure {
                if snapshot.failureIsSentence {
                     
                     
                    Label {
                        Text(clash: failure)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                            .foregroundStyle(Color.red)
                    }
                    .font(.subheadline)
                } else {
                     
                    Text(clash: failure)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            switch snapshot.source {
            case .local:
                 
                Button {
                    perform(.editModule(id: snapshot.id))
                } label: {
                    Text("Edit")
                }
                .accessibilityIdentifier("modules.detail.edit")
            case .link:
                 
                Button {
                    perform(.refreshModule(id: snapshot.id))
                } label: {
                    Text(clash: snapshot.isUpdating ? "Updating…" : "Update")
                }
                .disabled(snapshot.isUpdating)
                .accessibilityIdentifier("modules.detail.update")
            case .unknown:
                 
                EmptyView()
            }
        }
    }

     
     
    nonisolated static func sourceText(_ snapshot: ClashModuleDetailSnapshot, locale: Locale) -> String? {
        switch snapshot.source {
        case .link(let link): return link
        case .local: return ClashCopy.string("Local", locale: locale)
        case .unknown: return nil
        }
    }

    private func itemRow(_ item: ClashModuleDetailSnapshot.Item) -> some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            moduleWords(item.text)
                .font(.system(.callout, design: .monospaced))
            if let detail = item.detail {
                if case .verbatim(let words) = detail {
                     
                    moduleWords(words)
                        .font(.footnote)
                } else {
                     
                    Text(clash: detail)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let secondary = item.secondary {
                 
                moduleWords(secondary)
                    .font(.system(.caption, design: .monospaced))
            }
            if let place = item.place {
                Text(clash: place)
                    .font(.caption)
            }
            if let action = item.action {
                 
                 
                Button {
                    perform(.notice(action))
                } label: {
                    Text(clash: item.actionTitle ?? "Run Again")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("modules.detail.item.action.\(item.id)")
            }
        }
    }

     
     
     
     
    private func moduleWords(_ words: String) -> some View {
        Text(unhyphenated: Self.drawn(words))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(verbatim: words))
#if os(iOS) || os(macOS)
            .contextMenu {
                Button {
                    perform(.copy(words))
                } label: {
                    Text("Copy")
                }
                .accessibilityIdentifier("modules.detail.item.copy")
            }
#endif
    }

     
     
     
     
     
     
     
    nonisolated static func drawn(_ words: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in words.unicodeScalars {
            out.append(scalar)
            switch scalar {
            case ",": out.append("\u{200B}")
            case "-", "|", "$": out.append("\u{2060}")
            default: break
            }
        }
        return String(out)
    }

     
     
     
     
     
     
    nonisolated static func countsLine(effective: Int, skipped: Int, waiting: Int = 0, unavailable: Int = 0,
                                       waitsFor: ClashModuleDecryptionWait? = nil, enabled: Bool = true,
                                       locale: Locale) -> [ClashDisplayText] {
        ClashModuleCountLine.parts(kept: effective, waiting: waiting, unavailable: unavailable, waitsFor: waitsFor,
                                   enabled: enabled, skipped: skipped, details: true, locale: locale)
    }

    private func countsText(_ snapshot: ClashModuleDetailSnapshot) -> String {
        ClashModuleCountLine.string(
            Self.countsLine(effective: snapshot.effectiveCount, skipped: snapshot.ignoredCount,
                            waiting: snapshot.needsDecryptionCount, unavailable: snapshot.unavailableCount,
                            waitsFor: snapshot.waitsFor, enabled: snapshot.enabled, locale: locale),
            locale: locale)
    }

     

     
    struct Author: Equatable {
        var name: String
        var link: URL?
    }

     
     
     
     
     
     
    nonisolated static func authors(_ written: String) -> [Author]? {
        var pieces: [Substring] = []
        var depth = 0
        var start = written.startIndex
        for index in written.indices {
            switch written[index] {
            case "[": depth += 1
            case "]": depth -= 1
            case "," where depth == 0, "，" where depth == 0:
                pieces.append(written[start..<index])
                start = written.index(after: index)
            default: break
            }
            if depth < 0 || depth > 1 { return nil }
        }
        guard depth == 0 else { return nil }
        pieces.append(written[start...])
        var authors: [Author] = []
        for piece in pieces {
            let piece = piece.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { return nil }
            guard let open = piece.firstIndex(of: "[") else {
                if piece.contains("]") { return nil }
                authors.append(Author(name: piece, link: nil))
                continue
            }
            let name = piece[..<open].trimmingCharacters(in: .whitespaces)
            guard piece.hasSuffix("]"), !name.isEmpty else { return nil }
            let address = String(piece[piece.index(after: open)..<piece.index(before: piece.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            guard let link = URL(string: address), let scheme = link.scheme?.lowercased(),
                  scheme == "https" || scheme == "http", link.host != nil else { return nil }
            authors.append(Author(name: name, link: link))
        }
        return authors.contains { $0.link != nil } ? authors : nil
    }

     
     
    private func authorText(_ written: String) -> some View {
        Group {
            if let authors = Self.authors(written) {
                Text(Self.linked(authors))
            } else {
                Text(verbatim: written)
            }
        }
        .accessibilityLabel(Text(verbatim: written))
#if os(iOS) || os(macOS)
        .contextMenu {
            Button {
                perform(.copy(written))
            } label: {
                Text("Copy")
            }
        }
#endif
    }

    nonisolated static func linked(_ authors: [Author]) -> AttributedString {
        var text = AttributedString()
        for (index, author) in authors.enumerated() {
            if index > 0 { text += AttributedString(", ") }
            var name = AttributedString(author.name)
            name.link = author.link
            text += name
        }
        return text
    }

     
     
    nonisolated static func headerNote(_ section: ClashModuleDetailSnapshot.Section) -> ClashDisplayText? {
        section.waiting
    }

     
    nonisolated static func timeTitle(_ snapshot: ClashModuleDetailSnapshot) -> ClashDisplayText {
        switch snapshot.source {
        case .local: return "Saved"
        case .link, .unknown: return "Updated"
        }
    }

     
     
    @ViewBuilder
    private func valueRow<Value: View>(_ title: ClashDisplayText, @ViewBuilder value: () -> Value) -> some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            LabeledContent { value() } label: { Text(clash: title) }
        } else {
            valueRowBefore16(title, value: value())
        }
    }

    private func valueRowBefore16<Value: View>(_ title: ClashDisplayText, value: Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(clash: title)
            Spacer(minLength: ClashTheme.Spacing.row)
            value.foregroundStyle(.secondary)
        }
    }
}

#if os(macOS)
 
 
 
 
 
 
 
 
 
 
 
 
 
 
extension ClashModuleDetailView {
     
    enum Mac {
        static let width: CGFloat = 560
        static let height: CGFloat = 712
        static let top: CGFloat = 22
        static let bottom: CGFloat = 16
         
        static let groupGap: CGFloat = 18
         
        static let headerGap: CGFloat = 6
    }

     
    enum MacFact: Identifiable {
        case author(String)
        case link(String)
        case updated(Date?)
        case local
        case saved(Date)
        case failure(ClashDisplayText, sentence: Bool)
         
        case date(String)
        case homepage(String)
        case entries

        var id: String {
            switch self {
            case .author: return "author"
            case .link: return "link"
            case .updated: return "updated"
            case .local: return "local"
            case .saved: return "saved"
            case .failure: return "failure"
            case .date: return "date"
            case .homepage: return "homepage"
            case .entries: return "entries"
            }
        }
    }

     
     
    nonisolated static func macFacts(_ snapshot: ClashModuleDetailSnapshot) -> [MacFact] {
        var facts: [MacFact] = []
        if let author = snapshot.author { facts.append(.author(author)) }
        switch snapshot.source {
        case .link(let link):
            facts.append(.link(link))
            facts.append(.updated(snapshot.updatedAt))
        case .local:
            facts.append(.local)
            if let saved = snapshot.updatedAt { facts.append(.saved(saved)) }
        case .unknown:
             
            break
        }
        if let failure = snapshot.failure { facts.append(.failure(failure, sentence: snapshot.failureIsSentence)) }
        if let date = snapshot.date { facts.append(.date(date)) }
        if let homepage = snapshot.homepage { facts.append(.homepage(homepage)) }
        facts.append(.entries)
        return facts
    }

    var macSheet: some View {
        VStack(spacing: 0) {
            List {
                if let snapshot {
                    macHeader(snapshot)
                        .padding(.top, Mac.top)
                        .padding(.bottom, Mac.groupGap)
                        .padding(.horizontal, ClashMacGroupMetrics.margin)
                        .clashMacPlainRow()
                    let facts = Self.macFacts(snapshot)
                    ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                        macFactRow(fact, snapshot)
                            .clashMacGroupRow(first: index == 0, last: index == facts.count - 1)
                    }
                    if !snapshot.panels.isEmpty {
                        ClashModuleMacPanelsGroup(panels: snapshot.panels) { perform(.refreshPanel(id: $0)) }
                    }
                    if let settings = snapshot.settings {
                        ClashModuleMacSettingsGroup(moduleID: snapshot.id, settings: settings, perform: perform)
                    }
                    ForEach(snapshot.sections) { section in
                        macSectionHeader(section)
                            .padding(.top, Mac.groupGap)
                            .padding(.bottom, Mac.headerGap)
                            .padding(.horizontal, ClashMacGroupMetrics.margin + ClashTheme.Spacing.tight)
                            .clashMacPlainRow()
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            macItemRow(item, in: section)
                                .clashMacGroupRow(first: index == 0, last: index == section.items.count - 1)
                        }
                    }
                    Color.clear
                        .frame(height: Mac.bottom)
                        .clashMacPlainRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
             
             
            .environment(\.defaultMinListRowHeight, 0)
            Divider()
            macBar
        }
        .frame(minWidth: 480, idealWidth: Mac.width, minHeight: 420, idealHeight: Mac.height)
        .onExitCommand(perform: close)
         
         
         
        .task(id: snapshot?.id) {
            if let id = snapshot?.id { perform(.panelsAppeared(module: id)) }
        }
    }

     
    private func macHeader(_ snapshot: ClashModuleDetailSnapshot) -> some View {
        HStack(alignment: .top, spacing: ClashTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(verbatim: snapshot.name)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = snapshot.summary {
                     
                    Text(verbatim: summary)
                        .font(.callout)
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: Binding(get: { snapshot.enabled },
                                 set: { perform(.setModule(id: snapshot.id, enabled: $0)) })) {
                Text(verbatim: snapshot.name)
            }
            .modifier(ClashModulesSwitchStyle())
            .labelsHidden()
            .controlSize(.small)
            .padding(.top, 2)
            .accessibilityIdentifier("modules.detail.toggle")
        }
    }

     
     
     
    @ViewBuilder
    private func macFactRow(_ fact: MacFact, _ snapshot: ClashModuleDetailSnapshot) -> some View {
        switch fact {
        case .author(let author):
            macFact("Author") { authorText(author) }
        case .link(let link):
            macFact("Source") {
                 
                Text(unhyphenated: link)
                    .foregroundStyle(.secondary)
            }
        case .updated(let updated):
            macFact("Updated") {
                if let updated {
                    Text(updated, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                 
                Button {
                    perform(.refreshModule(id: snapshot.id))
                } label: {
                    Text(clash: snapshot.isUpdating ? "Updating…" : "Update")
                }
                .controlSize(.small)
                .clashMacFormActionChrome()
                .disabled(snapshot.isUpdating)
                .accessibilityIdentifier("modules.detail.update")
            }
        case .local:
            macFact("Source") {
                Text("Local")
                    .foregroundStyle(.secondary)
                 
                Button {
                    perform(.editModule(id: snapshot.id))
                } label: {
                    Text("Edit")
                }
                .controlSize(.small)
                .clashMacFormActionChrome()
                .accessibilityIdentifier("modules.detail.edit")
            }
        case .saved(let saved):
            macFact("Saved") {
                Text(saved, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
        case .failure(let failure, let sentence):
             
             
             
            HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
                Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                    .foregroundStyle(Color.red)
                Text(clash: failure)
                    .foregroundStyle(sentence ? Color.primary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .date(let date):
            macFact("Version Date") {
                Text(verbatim: date)
                    .foregroundStyle(.secondary)
            }
        case .homepage(let homepage):
            macFact("Homepage") {
                 
                if let url = ClashModuleInformationSection.webAddress(homepage) {
                    Link(destination: url) {
                        Text(unhyphenated: homepage)
                    }
                    .accessibilityIdentifier("modules.detail.homepage")
                } else {
                    Text(unhyphenated: homepage)
                        .foregroundStyle(.secondary)
                }
            }
        case .entries:
            macFact("Entries") {
                Text(verbatim: countsText(snapshot))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func macFact<Value: View>(_ title: ClashDisplayText, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .center, spacing: ClashTheme.Spacing.standard) {
            Text(clash: title)
            Spacer(minLength: 0)
            HStack(spacing: ClashTheme.Spacing.compact) {
                value()
            }
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

     
     
    private func macSectionHeader(_ section: ClashModuleDetailSnapshot.Section) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
            Text(clash: section.title)
                .fontWeight(.semibold)
            Spacer(minLength: ClashTheme.Spacing.compact)
            if let note = Self.headerNote(section) {
                Text(clash: note)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: ClashCopy.count(section.items.count, locale: locale))
                .foregroundStyle(.secondary)
        }
    }

     
     
    private func macItemRow(_ item: ClashModuleDetailSnapshot.Item, in section: ClashModuleDetailSnapshot.Section) -> some View {
        let named = section.id == "scripts" || section.id == "appScripts"
        return VStack(alignment: .leading, spacing: 2) {
            if named {
                moduleWords(item.text)
            } else {
                moduleWords(item.text)
                    .font(.system(.callout, design: .monospaced))
            }
            if let detail = item.detail {
                if case .verbatim(let words) = detail {
                     
                    moduleWords(words)
                        .font(.system(.subheadline, design: .monospaced))
                } else {
                     
                    Text(clash: detail)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let secondary = item.secondary {
                 
                moduleWords(secondary)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineSpacing(2)
            }
            if let place = item.place {
                Text(clash: place)
                    .font(.callout)
            }
            if let action = item.action {
                Button {
                    perform(.notice(action))
                } label: {
                    Text(clash: item.actionTitle ?? "Run Again")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("modules.detail.item.action.\(item.id)")
            }
        }
    }

     
     
     
    private var macBar: some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            if let snapshot {
                deleteButton(snapshot, title: "Delete Module…", destructive: false)
                    .clashMacFormActionChrome()
            }
            Spacer(minLength: 0)
            Button {
                close()
            } label: {
                Text("Done")
                    .frame(minWidth: 60)
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("modules.detail.done")
        }
        .padding(.horizontal, ClashMacGroupMetrics.margin)
        .padding(.vertical, ClashTheme.Spacing.row)
    }
}
 
 
 
 
struct ClashModuleMacPanelsGroup: View {
    let panels: [ClashModuleDetailSnapshot.Panel]
    let refresh: (String) -> Void

    var body: some View {
        Text("Panels")
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, ClashModuleDetailView.Mac.groupGap)
            .padding(.bottom, ClashModuleDetailView.Mac.headerGap)
            .padding(.horizontal, ClashMacGroupMetrics.margin + ClashTheme.Spacing.tight)
            .accessibilityIdentifier("modules.detail.panels")
            .clashMacPlainRow()
        ForEach(Array(panels.enumerated()), id: \.element.id) { index, panel in
            ClashModulePanelRow(panel: panel) { refresh(panel.id) }
                .clashMacGroupRow(first: index == 0, last: index == panels.count - 1)
        }
    }
}
 
 
 
 
 
 
 
struct ClashModuleMacSettingsGroup: View {
    let moduleID: String
    let settings: ClashModuleDetailSnapshot.Settings
    let perform: (ClashModulesAction) -> Void
    @State private var confirmsReset = false

    var body: some View {
        Text("Settings")
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, ClashModuleDetailView.Mac.groupGap)
            .padding(.bottom, ClashModuleDetailView.Mac.headerGap)
            .padding(.horizontal, ClashMacGroupMetrics.margin + ClashTheme.Spacing.tight)
            .clashMacPlainRow()
        let rows = settings.items.count + (settings.refusal == nil ? 0 : 1)
        ForEach(Array(settings.items.enumerated()), id: \.element.id) { index, setting in
            ClashModuleMacSettingRow(setting: setting) { value in
                perform(.setArgument(module: moduleID, name: setting.id, value: value))
            }
            .clashMacGroupRow(first: index == 0, last: index == rows - 1)
        }
        if let refusal = settings.refusal {
             
            HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
                Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                    .foregroundStyle(Color.red)
                Text(clash: refusal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("modules.detail.settings.refusal")
            .clashMacGroupRow(first: rows == 1, last: true)
        }
        if let note = settings.note {
             
            Text(verbatim: note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ClashTheme.Spacing.compact)
                .padding(.horizontal, ClashMacGroupMetrics.margin + ClashTheme.Spacing.tight)
                .clashMacPlainRow()
        }
        HStack {
            Spacer(minLength: 0)
            Button {
                confirmsReset = true
            } label: {
                Text("Reset…")
            }
            .controlSize(.small)
            .clashMacFormActionChrome()
            .disabled(!settings.canReset)
            .accessibilityIdentifier("modules.detail.settings.reset")
             
            .confirmationDialog(
                Text("Reset this module's settings?"),
                isPresented: $confirmsReset,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    perform(.resetArguments(module: moduleID))
                } label: {
                    Text("Reset")
                }
                .accessibilityIdentifier("modules.detail.settings.reset.confirm")
                Button(role: .cancel) {} label: {
                    Text("Cancel")
                }
            }
        }
        .padding(.top, ClashTheme.Spacing.compact)
        .padding(.horizontal, ClashMacGroupMetrics.margin)
        .clashMacPlainRow()
    }
}

 
 
 
 
struct ClashModuleMacSettingRow: View {
    let setting: ClashModuleDetailSnapshot.Setting
    let commit: (String?) -> Void
    @State private var draft = ""
     
    @State private var sent: String??
    @FocusState private var editing: Bool

     
    static let fieldWidth: CGFloat = 200

    var body: some View {
        HStack(alignment: .center, spacing: ClashTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: setting.title)
                if let note = setting.note {
                    Text(verbatim: note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = setting.defaultLine {
                    Text(clash: line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        switch setting.control {
        case .toggle(let isOn):
            Toggle(isOn: Binding(get: { isOn }, set: { commit($0 ? "true" : "false") })) {
                Text(verbatim: setting.title)
            }
            .modifier(ClashModulesSwitchStyle())
            .labelsHidden()
            .controlSize(.small)
            .accessibilityIdentifier("modules.detail.setting.\(setting.id)")
        case .menu(let options, let selected):
            Picker(selection: Binding(get: { selected }, set: { commit($0) })) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(verbatim: option).tag(option)
                }
            } label: {
                Text(verbatim: setting.title)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("modules.detail.setting.\(setting.id)")
        case .text(let value, let placeholder):
            TextField(text: $draft, prompt: Text(clash: placeholder)) {
                Text(verbatim: setting.title)
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .disableAutocorrection(true)
            .frame(width: Self.fieldWidth)
            .focused($editing)
            .onSubmit { send(from: value) }
            .onChange(of: editing) { if !$0 { send(from: value) } }
            .onChange(of: value) { if !editing { draft = $0 } }
            .onAppear { draft = value }
            .onDisappear { send(from: value) }
            .accessibilityIdentifier("modules.detail.setting.\(setting.id)")
        }
    }

     
    private func send(from value: String) {
        let given: String? = draft.isEmpty ? nil : draft
        guard draft != value, sent != .some(given) else { return }
        sent = .some(given)
        commit(given)
    }
}
#endif

struct ClashModulesListStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.listStyle(.insetGrouped)
#elseif os(macOS)
        content.listStyle(.inset)
#else
        content.listStyle(.grouped)
#endif
    }
}

extension Text {
     
     
     
     
     
     
    init(unhyphenated value: String) {
        var text = AttributedString(value)
        text.languageIdentifier = "zxx"
        self.init(text)
    }
}
