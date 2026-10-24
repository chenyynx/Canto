import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
struct ClashMacKeptRulesList: View {
    let kept: ProfilesViewModel.ConfigurationEditorPage.KeptRules
    @StateObject private var pager = KeptRulesPager()
    @State private var search = ""
    @Environment(\.locale) private var locale

     
    static let note: ClashDisplayText =
        .copy("These rules are too many to edit one by one here. They run as written in the configuration's file.")

    private var header: ClashDisplayText {
        let query = pager.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty, let matched = pager.matched {
             
            return .format(matched == 1 ? "%@ match" : "%@ matches", [matched.formatted(.number.locale(locale))])
        }
        return .format("%@ rules", [(pager.total ?? kept.count).formatted(.number.locale(locale))])
    }

    var body: some View {
        List {
            Section {
                ForEach(pager.rules, id: \.index) { entry in
                     
                    ConfigurationRuleRow(entry.rule, showsChevron: false)
                        .accessibilityIdentifier("configuration-center.kept-rules.row")
                        .onAppear {
                            if entry.index == pager.rules.last?.index { Task { await pager.more() } }
                        }
                }
                if pager.matched == 0 {
                    Text(clash: .copy("No matching rules")).foregroundStyle(.secondary)
                }
                if let failure = pager.failure {
                    Text(verbatim: failure).foregroundStyle(.secondary)
                }
                if pager.loading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("configuration-center.kept-rules.loading")
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clash: header).accessibilityIdentifier("configuration-center.kept-rules.count")
                    Text(clash: Self.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .listStyle(.inset)
         
         
         
        .clashProductModalSearchable(text: $search, prompt: Text("Search rules"))
        .task(id: search) {
             
            if !pager.rules.isEmpty || pager.failure != nil {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }
            await pager.load(file: kept.file, query: search)
        }
        .onDisappear { pager.close() }
        .accessibilityIdentifier("configuration-center.kept-rules")
    }
}
