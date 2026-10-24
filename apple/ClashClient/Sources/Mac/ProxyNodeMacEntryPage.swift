import ClashClientKit
import ClashMacClient
import SwiftUI

 
 
 
 
 
 
 
 
 
struct ProxyNodeMacEntryPage: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    let path: [String]
     
    let field: ConfigurationField
    let title: String

    private var value: OrderedJSON? { draft.value(path: path).flatMap(ProxyNodeCatalog.json) }

    var body: some View {
        ProxyEditorSeat {
            ClashMacEntryRows(value: value, field: field,
                             catalog: ProfilesViewModel.rememberedSyntaxCatalog?.fieldCatalog, save: save)
        }
        .navigationTitle(Text(verbatim: title))
    }

     
    private func save(_ next: OrderedJSON?) { Self.apply(next, to: draft, path: path) }

     
     
     
     
     
     
    static func apply(_ next: OrderedJSON?, to draft: ProxyNodeEditorDraft, path: [String]) {
        guard let next else {
            draft.removeValue(path: path)
            return
        }
        guard let data = next.serialized().data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return }
        draft.replaceJSONValue(object, path: path)
    }
}
