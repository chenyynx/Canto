import ClashClientUI
import SwiftUI

 
 
 
 
 
struct ModuleAddModuleSheet: View {
    enum Input: Equatable {
        case link(String)
        case text(String)
    }

    let isAdding: Bool
    let refusal: ClashDisplayText?
     
     
    let offeredLink: String?
    let add: (Input) -> Void
    let cancel: () -> Void
    let edited: () -> Void
    @State private var link: String
     
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal

    init(isAdding: Bool, refusal: ClashDisplayText?, offeredLink: String? = nil, add: @escaping (Input) -> Void,
         cancel: @escaping () -> Void, edited: @escaping () -> Void) {
        self.isAdding = isAdding
        self.refusal = refusal
        self.offeredLink = offeredLink
        self.add = add
        self.cancel = cancel
        self.edited = edited
        _link = State(initialValue: offeredLink ?? "")
    }

    private var typedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ClashClientUI.ClashSingleColumnNavigationContainer {
            Form {
                Section {
                     
                     
                     
                     
                    HStack(spacing: ClashTheme.Spacing.standard) {
                        linkField
                        ClashPasteControl(style: .square) { pasted in
                            let input = Self.input(forPasted: pasted)
                            if case .link(let value) = input { link = value }
                            add(input)
                        }
                        .disabled(isAdding)
                        .accessibilityIdentifier("modules.add.paste")
                    }
                } footer: {
                    if let refusal {
                        Text(clash: refusal)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("modules.add.refusal")
                    } else {
                        Text("Paste a link to a module, or the module itself.")
                    }
                }
            }
            .clashPageTitle("Add Module")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) {
                        Text("Cancel")
                    }
                    .accessibilityIdentifier("modules.add.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button {
                            add(.link(typedLink))
                        } label: {
                            Text("Add")
                        }
                        .disabled(typedLink.isEmpty)
                        .accessibilityIdentifier("modules.add.confirm")
                    }
                }
            }
            .clashMacProductModalBar {
                if insideProductModal {
                    ClashModalActionBar(primaryTitle: "Add", primaryDisabled: typedLink.isEmpty, isBusy: isAdding,
                                        onPrimary: { add(.link(typedLink)) })
                }
            }
            .clashProductModalRoot(title: "Add Module", actionTitle: "Add",
                                  actionDisabled: isAdding || typedLink.isEmpty,
                                  action: { add(.link(typedLink)) })
        }
    }

    private var linkField: some View {
        TextField(text: $link, prompt: Self.prompt) {
            Text("Module Link")
        }
        .disableAutocorrection(true)
#if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.URL)
        .textContentType(.URL)
#endif
        .onChange(of: link) { _ in edited() }
        .onChange(of: offeredLink) { offered in
            if let offered { link = offered }
        }
        .onSubmit { if !typedLink.isEmpty { add(.link(typedLink)) } }
        .accessibilityIdentifier("modules.add.link")
    }

     
     
     
     
    static var prompt: Text {
        #if os(macOS)
        Text(verbatim: "https://…")
        #else
        Text("Module Link")
        #endif
    }

     
     
    static func input(forPasted pasted: String) -> Input {
        if let carried = ModuleInstallLink.moduleLink(in: pasted) { return .link(carried) }
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("\n"), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host?.isEmpty == false {
            return .link(trimmed)
        }
        return .text(pasted)
    }
}

 
 
 
 
 
 
 
 
 
enum ModuleInstallLink {
    private static let schemes: Set<String> = [#"clash"#, #"clash"#]
    private static let name = #"install-module"#

     
     
     
    static func moduleLink(from link: URL) -> String? {
        guard let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
              schemes.contains(components.scheme?.lowercased() ?? "") else { return nil }
        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        guard host == name && (path.isEmpty || path == #"/"#) || host.isEmpty && path == #"/"# + name else { return nil }
        let carried = components.queryItems?.first(where: { $0.name == #"url"# })?.value ?? ""
        return carried.trimmingCharacters(in: .whitespacesAndNewlines)
    }

     
     
    static func moduleLink(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"), let url = URL(string: trimmed),
              let carried = moduleLink(from: url), !carried.isEmpty else { return nil }
        return carried
    }
}
