import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashAddRow<TouchLabel: View>: View {
     
     
     
     
     
     
     
     
     
    public enum Context {
        case formRow
        case standaloneCard
    }

    private let title: Text
    private let symbol: ClashSymbol?
    private let context: Context
    private let action: () -> Void
    private let touchLabel: () -> TouchLabel

    public init(
        _ title: Text,
        symbol: ClashSymbol? = nil,
        context: Context = .formRow,
        action: @escaping () -> Void,
        @ViewBuilder touchLabel: @escaping () -> TouchLabel
    ) {
        self.title = title
        self.symbol = symbol
        self.context = context
        self.action = action
        self.touchLabel = touchLabel
    }

    public var body: some View {
#if os(macOS)
         
         
         
         
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            Button(action: action) {
                HStack(spacing: ClashTheme.Spacing.row) {
                    Image(systemName: (symbol ?? .plus).rawValue)
                    title
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.primary)
        } else {
        Button(action: action) {
            standardLabel
        }
        .buttonStyle(.plain)
        }
#else
         
         
         
         
         
         
        Button(action: action) {
            if TouchLabel.self == EmptyView.self {
                standardLabel
            } else {
                touchLabel()
            }
        }
#endif
    }

     
     
     
    private var standardLabel: some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            Image(systemName: ClashSymbol.plusCircleFill.rawValue)
                .font(.title3)
            title
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tint)
        .padding(
            context == .standaloneCard
                ? EdgeInsets(
                    top: ClashTheme.Spacing.standard,
                    leading: ClashTheme.Spacing.standard,
                    bottom: ClashTheme.Spacing.standard,
                    trailing: ClashTheme.Spacing.standard
                )
                : EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
        )
        .frame(
            maxWidth: .infinity,
             
             
            minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform,
            alignment: .leading
        )
         
         
         
        .contentShape(Rectangle())
    }
}

public extension ClashAddRow where TouchLabel == EmptyView {
     
     
    init(
        _ title: Text,
        symbol: ClashSymbol? = nil,
        context: Context = .formRow,
        action: @escaping () -> Void
    ) {
        self.init(
            title,
            symbol: symbol,
            context: context,
            action: action,
            touchLabel: { EmptyView() }
        )
    }
}

