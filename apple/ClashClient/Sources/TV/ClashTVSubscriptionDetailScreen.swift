import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVSubscriptionDetailScreen: View {
     
     
     
     
    enum Verb: Hashable, CaseIterable {
        case script
        case rules
        case update
        case autoUpdate
        case edit
        case use
        case remove

        var title: String {
            switch self {
            case .script: String(localized: "Script")
            case .update: String(localized: "Update now")
            case .rules: String(localized: "Rules")
            case .autoUpdate: String(localized: "Auto update")
            case .edit: String(localized: "Edit")
            case .use: String(localized: "Use this profile")
            case .remove: String(localized: "Remove")
            }
        }

        var identifier: String {
            switch self {
            case .script: "script"
            case .update: "update"
            case .rules: "rules"
            case .autoUpdate: "auto-update"
            case .edit: "edit"
            case .use: "use"
            case .remove: "remove"
            }
        }
    }

    @Binding var store: ClashTVSubscriptionStore
    let id: ClashTVSubscription.ID
     
     
    var refresh: ClashTVProductState.Refresh?
     
    var onDone: () -> Void = {}
     
     
     
    var onUpdate: (() -> Void)?
     
    var onEdit: () -> Void = {}
     
    var onRules: () -> Void = {}
    var onAutoUpdate: () -> Void = {}
     
     
    var onScript: () -> Void = {}
     
     
     
     
    var feedback: ClashFeedbackPresentation?

    @State private var asksToRemove = false

    private var subscription: ClashTVSubscription? {
        store.subscriptions.first { $0.id == id }
    }

    private var isCurrent: Bool { store.current?.id == id }

    private var isUpdating: Bool {
        if case .updating(let which, _) = refresh, which == id { return true }
        return false
    }

    private var updateFailure: String? {
        if case .failed(let which, let reason) = refresh, which == id { return reason }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            actions
            explanation
        }
        .alert(Self.removeQuestion, isPresented: $asksToRemove) {
            Button(Verb.remove.title, role: .destructive) {
                store.remove(id)
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.removeMessage(title: subscription?.title ?? ""))
        }
         
    }

    private var actions: some View {
        List {
             
             
            ForEach(Array(Self.sections(isCurrent: isCurrent, isFetchable: subscription?.hasFetchableAddress ?? false).enumerated()), id: \.offset) { _, verbs in
                Section {
                    ForEach(verbs, id: \.self) { verb in
                        Button(role: verb == .remove ? .destructive : nil) {
                            perform(verb)
                        } label: {
                            row(for: verb)
                        }
                         
                         
                         
                         
                         
                        .accessibilityIdentifier("tvos.subscription.\(verb.identifier)")
                    }
                }
            }
        }
        .listStyle(.grouped)
        .safeAreaPadding(.horizontal, 44)
        .frame(maxWidth: .infinity)
    }

     
     
    @ViewBuilder
    private func row(for verb: Verb) -> some View {
        switch verb {
        case .update:
            HStack(spacing: 16) {
                if isUpdating { ProgressView() }
                Text(Self.updateRowTitle(updating: isUpdating))
            }
        case .script:
            trailing(verb.title, subscription.map(ClashTVProfileScriptScreen.rowValue(for:)) ?? "")
        case .rules:
            trailing(verb.title, subscription?.effectiveRules.title ?? "")
        case .autoUpdate:
            trailing(verb.title, ClashTVAutoUpdateScreen.title(forHours: subscription?.updateIntervalHours ?? 0))
        default:
            Text(verb.title)
        }
    }

    private func trailing(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func perform(_ verb: Verb) {
        switch verb {
        case .update:
            guard !isUpdating else { return }
            if let onUpdate {
                onUpdate()
            } else {
                store.markUpdated(id, at: Date())
            }
        case .script:
            onScript()
        case .rules:
            onRules()
        case .autoUpdate:
            onAutoUpdate()
        case .edit:
            onEdit()
        case .use:
            store.use(id)
            onDone()
        case .remove:
            asksToRemove = true
        }
    }

     
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            if let subscription {
                Text(subscription.title)
                    .font(.title2)
                 
                 
                Text(subscription.displayURL.absoluteString)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                Text(Self.status(isCurrent: isCurrent))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(ClashTVSubscriptionUpdatedWords.text(updatedAt: subscription.updatedAt))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tvos.subscription.updated")
                 
                 
                Text(Self.scriptLine(for: subscription))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tvos.subscription.script")
                if let updateFailure {
                     
                     
                     
                    Text(Self.updateFailure(updateFailure))
                        .font(.body)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("tvos.subscription.updateFailure")
                }
                if let shown = Self.feedbackToDraw(feedback, statusShowsFailure: updateFailure != nil) {
                    ClashTVFeedbackLine(presentation: shown)
                }
            } else {
                Text("This profile is no longer on this Apple TV.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

     

     
     
     
    static func feedbackToDraw(_ feedback: ClashFeedbackPresentation?, statusShowsFailure: Bool) -> ClashFeedbackPresentation? {
        guard let feedback else { return nil }
        if feedback.accessibilityIdentifier == ClashTVFeedback.updatedIdentifier { return nil }
        if feedback.kind == .error, statusShowsFailure { return nil }
        return feedback
    }

     
     
     
     
     
     
    static func scriptLine(for subscription: ClashTVSubscription) -> String {
        let value = subscription.scriptURL?.host ?? String(localized: "None")
        return "\(String(localized: "Override script")) · \(value)"
    }

     
     
     
    static func sections(isCurrent: Bool, isFetchable: Bool = true) -> [[Verb]] {
        let document: [Verb] = isFetchable ? [.script, .rules] : []
        var row: [Verb] = isCurrent ? [.update, .autoUpdate, .edit] : [.autoUpdate, .edit, .use]
        if !isFetchable { row.removeAll { $0 == .autoUpdate } }
        return [document, row, [.remove]].filter { !$0.isEmpty }
    }

     
    static func verbs(isCurrent: Bool, isFetchable: Bool = true) -> [Verb] {
        sections(isCurrent: isCurrent, isFetchable: isFetchable).flatMap { $0 }
    }

    static func updateRowTitle(updating: Bool) -> String {
        updating ? String(localized: "Updating…") : Verb.update.title
    }

     
    static func updateFailure(_ reason: String) -> String {
        String(localized: "Could not update: \(reason)")
    }

    static var removeQuestion: String { String(localized: "Remove this profile?") }

     
     
     
    static func removeMessage(title: String) -> String {
        String(localized: "Remove “\(title)”? This Apple TV forgets the address. To bring it back, type it again.")
    }

     
    static func status(isCurrent: Bool) -> String {
        isCurrent
            ? String(localized: "In use. Clash updates this profile from this link.")
            : String(localized: "Not in use. The address stays remembered.")
    }
}
