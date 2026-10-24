import SwiftUI

 
public struct ClashNodeScriptResult: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable {
        case running
         
         
         
         
        case finished(title: String?, message: ClashScriptHTML.Rendered?)
         
         
        case failed(ClashDisplayText, detail: String?)
    }

    public var id: UUID
    public var scriptName: String
    public var node: String
    public var state: State

    public init(id: UUID = UUID(), scriptName: String, node: String, state: State) {
        self.id = id
        self.scriptName = scriptName
        self.node = node
        self.state = state
    }

     
     
    public var subject: String {
        pageTitle == scriptName ? node : "\(scriptName) · \(node)"
    }

     
    public var pageTitle: String {
        if case .finished(let title?, _) = state, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return scriptName
    }
}

 
 
 
public struct ClashNodeScriptResultView: View {
    public let result: ClashNodeScriptResult

    public init(result: ClashNodeScriptResult) {
        self.result = result
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                 
                 
                Text(verbatim: result.subject)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("proxies.script.result.subject")
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ClashTheme.Spacing.standard)
        }
        .accessibilityIdentifier("proxies.script.result")
    }

    @ViewBuilder
    private var content: some View {
        switch result.state {
        case .running:
            HStack(spacing: ClashTheme.Spacing.compact) {
                ProgressView()
                Text("Running")
                    .foregroundStyle(.secondary)
            }
        case .finished(_, let rendered?) where !rendered.text.characters.isEmpty:
            Text(rendered.text)
                .multilineTextAlignment(rendered.centered ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: rendered.centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("proxies.script.result.message")
        case .finished:
            Text("The script ran and returned nothing.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let sentence, let detail):
            Label {
                Text(clash: sentence)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                    .foregroundStyle(Color.orange)
            }
            if let detail, !detail.isEmpty {
                 
                Text(verbatim: detail)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}
