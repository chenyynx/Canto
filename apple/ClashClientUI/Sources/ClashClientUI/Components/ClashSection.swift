import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashSection<Content: View, Footer: View>: View {
    private let title: String
    private let content: Content
    private let footer: Footer

    public init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.title = title
        self.content = content()
        self.footer = EmptyView()
    }

     
     
     
     
     
    public init(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

#if os(macOS)
    @Environment(\.clashMacSectionCard) private var macSectionCard
#endif

    public var body: some View {
#if os(macOS)
        if let card = macSectionCard {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                if !title.isEmpty {
                    ClashSectionTitle(title: title)
                }
                ClashCardSurface(
                    fill: card.fill,
                    separator: card.separator,
                    paintsInSettingsIdiom: true
                ) {
                     
                     
                     
                     
                     
                     
                    VStack(spacing: ClashTheme.Spacing.row) {
                        content
                    }
                    .padding(ClashTheme.Spacing.cardGap)
                }
                footer
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                content
            } header: {
                 
                 
                 
                if !title.isEmpty {
                    ClashSectionTitle(title: title)
                }
            } footer: {
                footer
            }
        }
#else
        Section {
            content
        } header: {
            Text(ClashCopy.key(title))
        } footer: {
            footer
        }
#endif
    }
}

#if os(macOS)
 
 
 
 
 
 
 
 
public struct ClashMacSectionCardStyle: Sendable {
    public let fill: Color
    public let separator: Color

    public init(fill: Color, separator: Color) {
        self.fill = fill
        self.separator = separator
    }
}

private struct ClashMacSectionCardKey: EnvironmentKey {
    static let defaultValue: ClashMacSectionCardStyle? = nil
}

extension EnvironmentValues {
    public var clashMacSectionCard: ClashMacSectionCardStyle? {
        get { self[ClashMacSectionCardKey.self] }
        set { self[ClashMacSectionCardKey.self] = newValue }
    }
}

 
 
 
 
 
 
 
 
 
private struct ClashSectionTitle: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
             
             
             
             
            Text(ClashCopy.key(title))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                 
                 
                .textCase(nil)
        }
        .padding(.top, ClashTheme.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
