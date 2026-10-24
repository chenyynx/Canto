import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
public struct ClashMacFeedbackBar: View {
    @ObservedObject private var center: ClashFeedbackCenter
     
    private let leadingInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(center: ClashFeedbackCenter, leadingInset: CGFloat = 0) {
        self.center = center
        self.leadingInset = leadingInset
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let entry = center.unclaimed {
                ClashMacFeedbackCapsule(entry: entry, center: center, fillsWidth: true)
                    .id(entry.id)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.leading, leadingInset)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.9), value: center.unclaimed?.id)
    }
}

 
 
 
 
public struct ClashMacFeedbackCapsule: View {
    let entry: ClashFeedbackCenterState.ShownResult
    @ObservedObject var center: ClashFeedbackCenter
     
    let fillsWidth: Bool
    @State private var showsAll = false
    @Environment(\.locale) private var locale

     
     
    private static let messageLines = 2

    public init(entry: ClashFeedbackCenterState.ShownResult, center: ClashFeedbackCenter, fillsWidth: Bool = false) {
        self.entry = entry
        self.center = center
        self.fillsWidth = fillsWidth
    }

    private var presentation: ClashFeedbackPresentation { entry.presentation }

    private var messageText: String? {
        presentation.message?.resolved(locale: locale)
    }

    private var hasMore: Bool {
        guard let messageText else { return false }
        return messageText.split(separator: "\n", omittingEmptySubsequences: false).count > Self.messageLines
            || messageText.count > 240
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ClashMacFeedbackSymbol(kind: presentation.kind)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(clash: presentation.title)
                    .font(.body.weight(.medium))
                if let message = presentation.message {
                    Text(clash: message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(Self.messageLines)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if fillsWidth { Spacer(minLength: 12) }
            if hasMore, presentation.action != .details, let messageText {
                Button { showsAll = true } label: { Text(clash: .copy("Details")) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                     
                     
                    .tint(.primary)
                    .popover(isPresented: $showsAll, arrowEdge: .bottom) {
                        ScrollView {
                            Text(verbatim: messageText)
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        .frame(width: 420)
                        .frame(maxHeight: 320)
                    }
                    .accessibilityIdentifier("feedback.details")
            }
             
            if let action = presentation.action, center.offersAction(entry.id) {
                Button { center.perform(entry.id) } label: {
                    Text(clash: ClashFeedbackCopy.title(for: action))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("feedback.action")
            }
            if presentation.kind != .loading {
                 
                 
                Button { center.dismiss(entry.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(clash: .copy("Dismiss")))
                .accessibilityLabel(Text(clash: .copy("Dismiss")))
                .accessibilityIdentifier("feedback.dismiss")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: fillsWidth ? .infinity : 560, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .onHover { inside in
            if inside { center.pause("pointer") } else { center.resume("pointer") }
        }
         
         
        .onDisappear { center.resume("pointer") }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

struct ClashMacFeedbackSymbol: View {
    let kind: ClashFeedbackPresentation.Kind

    var body: some View {
        switch kind {
        case .loading:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityHidden(true)
        case .information:
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .accessibilityHidden(true)
        case .error:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                .accessibilityHidden(true)
        }
    }
}

 
 
 
public struct ClashMacFeedbackSlot: View {
    @ObservedObject private var center: ClashFeedbackCenter
    private let operations: [String]

    public init(center: ClashFeedbackCenter, operations: [String]) {
        self.center = center
        self.operations = operations
    }

    public var body: some View {
         
         
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0)
            if let entry = operations.lazy.compactMap({ center.result(for: $0) }).first {
                ClashMacFeedbackCapsule(entry: entry, center: center)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clashFeedbackClaim(operations)
    }
}
