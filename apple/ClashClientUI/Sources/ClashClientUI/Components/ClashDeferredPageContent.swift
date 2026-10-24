import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashDeferredPageContent<Content: View, Placeholder: View>: View {
    @ViewBuilder private let content: () -> Content
    @ViewBuilder private let placeholder: () -> Placeholder

    @State private var ready = false

    public init(
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        if ClashPlatformLayout.dataPagesDeferContentOneTurn {
            Group {
                if ready {
                    content()
                } else {
                    placeholder()
                        .accessibilityIdentifier("page.deferred.placeholder")
                }
            }
            .task {
                 
                 
                 
                await Task.yield()
                guard !Task.isCancelled else { return }
                ready = true
            }
        } else {
            content()
        }
    }
}

 
 
 
 
 
 
public struct ClashPageLoadingPlaceholder: View {
    private let title: ClashDisplayText

    public init(title: ClashDisplayText) {
        self.title = title
    }

    public var body: some View {
        VStack(spacing: ClashTheme.Spacing.compact) {
            Spacer()
            Text(clash: title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
