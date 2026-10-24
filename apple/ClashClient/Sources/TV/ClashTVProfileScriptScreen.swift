import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
struct ClashTVProfileScriptScreen: View {
    @Binding var store: ClashTVSubscriptionStore
    let id: ClashTVSubscription.ID
     
     
    var onUpdateScript: (() -> Void)?
     
     
    var onDone: (ClashTVSubscription.ID?) -> Void = { _ in }
     
    var refresh: ClashTVProductState.Refresh?
     
     
    var feedback: ClashFeedbackPresentation?

    @State private var scriptText: String
    @State private var refusal: String?

    init(
        store: Binding<ClashTVSubscriptionStore>,
        id: ClashTVSubscription.ID,
        onUpdateScript: (() -> Void)? = nil,
        refresh: ClashTVProductState.Refresh? = nil,
        feedback: ClashFeedbackPresentation? = nil,
        onDone: @escaping (ClashTVSubscription.ID?) -> Void = { _ in }
    ) {
        _store = store
        self.id = id
        self.onUpdateScript = onUpdateScript
        self.refresh = refresh
        self.feedback = feedback
        self.onDone = onDone
        _scriptText = State(initialValue: Self.seedScript(for: id, in: store.wrappedValue))
    }

    private var isUpdating: Bool {
        if case .updating(let which, _) = refresh, which == id { return true }
        return false
    }

    private var hasScript: Bool {
        store.subscriptions.first { $0.id == id }?.scriptURL != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            form
            explanation
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Script URL")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            TextField("Script URL", text: $scriptText, prompt: Text("Optional"))
                .textInputAutocapitalization(.never)
                .onSubmit(save)
                .accessibilityIdentifier("tvos.subscription.script.address")
            Text("Type on your phone instead — the keyboard is already waiting there.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let refusal {
                Text(clash: .verbatim(refusal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tvos.subscription.script.refusal")
            }
            Button("Save", action: save)
                .padding(.top, 8)
                .accessibilityIdentifier("tvos.subscription.script.save")
            if hasScript {
                Button {
                     
                    guard !isUpdating else { return }
                    onUpdateScript?()
                } label: {
                    HStack(spacing: 16) {
                        if isUpdating { ProgressView() }
                        Text(isUpdating ? String(localized: "Updating…") : String(localized: "Update Script"))
                    }
                }
                .accessibilityIdentifier("tvos.subscription.script.update")
            }
            if let feedback {
                ClashTVFeedbackLine(presentation: feedback)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happens")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Text("The script at this address runs on the profile every time it is fetched, after the rules are applied. Leave it empty to run the profile as it comes. Update Script fetches the same address again.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func save() {
        do {
            let changed = try Self.save(id: id, text: scriptText, in: &store)
            refusal = nil
            onDone(changed ? id : nil)
        } catch {
            refusal = error.localizedDescription
        }
    }

     

     
    static func seedScript(for id: ClashTVSubscription.ID, in store: ClashTVSubscriptionStore) -> String {
        store.subscriptions.first { $0.id == id }?.scriptURL?.absoluteString ?? ""
    }

     
     
     
    @discardableResult
    static func save(id: ClashTVSubscription.ID, text: String, in store: inout ClashTVSubscriptionStore) throws -> Bool {
        let script = try ClashTVSubscriptionStore.scriptURL(from: text)
        let changed = script != store.subscriptions.first { $0.id == id }?.scriptURL
        store.setScriptURL(id, script)
        return changed
    }

     
    static func rowValue(for subscription: ClashTVSubscription) -> String {
        subscription.scriptURL?.host ?? String(localized: "None")
    }
}
