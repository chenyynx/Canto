import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
struct ClashMacSheetFrame<Content: View, Leading: View, Trailing: View>: View {
    let title: ClashDisplayText
    var subtitle: ClashDisplayText? = nil
    var width: CGFloat = 560
    var height: CGFloat = 520
    @ViewBuilder let content: () -> Content
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: ClashDisplayText,
        subtitle: ClashDisplayText? = nil,
        width: CGFloat = 560,
        height: CGFloat = 520,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.height = height
        self.content = content
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clash: title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(clash: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                leading().tint(.primary)
                Spacer()
                trailing()
            }
            .padding(20)
        }
        .frame(width: width, height: height)
    }
}

 
 
struct ClashMacSheetButtons: View {
    var closeTitle: ClashDisplayText = .copy("Cancel")
    var closeIdentifier: String
    var primaryTitle: ClashDisplayText? = nil
    var primaryIdentifier: String? = nil
    var primaryDisabled = false
    var isBusy = false
    var onClose: () -> Void
    var onPrimary: () -> Void = {}

    var body: some View {
        Button(action: onClose) { Text(clash: closeTitle) }
            .tint(.primary)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(closeIdentifier)
        if let primaryTitle {
            Button(action: onPrimary) { ClashActionProgressLabel(primaryTitle, isBusy: isBusy) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(primaryDisabled)
                .accessibilityIdentifier(primaryIdentifier ?? "")
        }
    }
}

 
 
 
struct ClashMacSheetForm<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }
}

 
 
 
struct ClashMacSheetPlaceholder: View {
    let title: ClashDisplayText
    var message: String? = nil
    var retry: (() -> Void)? = nil
    var retryIdentifier: String? = nil

    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label { Text(clash: title) } icon: { ClashSymbolImage(symbol: .docText) }
            } description: {
                if let message { Text(verbatim: message) }
            } actions: {
                if let retry {
                    Button(action: retry) { Text(clash: .copy("Retry")) }
                        .accessibilityIdentifier(retryIdentifier ?? "")
                }
            }
        } else {
            VStack(spacing: 8) {
                ClashSymbolImage(symbol: .docText)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(clash: title).font(.title3).fontWeight(.semibold)
                if let message {
                    Text(verbatim: message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if let retry {
                    Button(action: retry) { Text(clash: .copy("Retry")) }
                        .accessibilityIdentifier(retryIdentifier ?? "")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
