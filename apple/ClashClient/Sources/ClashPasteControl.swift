import ClashClientUI
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

 
 
 
 
 
 
public enum ClashPasteControlPolicy {
    public enum Mode: Equatable {
        case systemControl
        case directRead
    }

    public static func mode(majorSystemVersion: Int) -> Mode {
        majorSystemVersion >= 16 ? .systemControl : .directRead
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashPasteControl: View {
    public enum Style {
         
         
        case row
         
         
         
        case square
    }

    private let onPaste: (String) -> Void
    private let style: Style

    public init(style: Style = .row, onPaste: @escaping (String) -> Void) {
        self.style = style
        self.onPaste = onPaste
    }

     
     
    private static let squareSide: CGFloat = 34

    public var body: some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
             
             
             
             
             
             
             
             
             
            SystemPasteControl(onPaste: onPaste)
                .fixedSize()
                .accessibilityIdentifier("clash.paste")
        } else {
            Button {
                onPaste(UIPasteboard.general.string ?? "")
            } label: {
                if style == .square {
                    Image(systemName: ClashSymbol.docOnClipboard.name)
                        .foregroundStyle(.white)
                        .frame(width: Self.squareSide, height: Self.squareSide)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.tint)
                        )
                } else {
                    Image(systemName: ClashSymbol.docOnClipboard.name)
                }
            }
            .accessibilityLabel("Paste")
            .accessibilityIdentifier("clash.paste")
        }
#elseif os(macOS)
        Button {
            onPaste(NSPasteboard.general.string(forType: .string) ?? "")
        } label: {
            Image(systemName: ClashSymbol.docOnClipboard.name)
        }
         
         
        .buttonStyle(.bordered)
        .tint(.primary)
        .accessibilityLabel("Paste")
        .accessibilityIdentifier("clash.paste")
#else
        EmptyView()
#endif
    }
}

#if os(iOS)
@available(iOS 16.0, *)
private struct SystemPasteControl: UIViewRepresentable {
    let onPaste: (String) -> Void

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.cornerStyle = .medium
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
         
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            control.setContentHuggingPriority(.required, for: axis)
            control.setContentCompressionResistancePriority(.required, for: axis)
        }
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPaste: onPaste) }

     
     
    final class Coordinator: UIResponder {
        var onPaste: (String) -> Void

        init(onPaste: @escaping (String) -> Void) {
            self.onPaste = onPaste
            super.init()
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        }

        override func paste(itemProviders: [NSItemProvider]) {
            for provider in itemProviders
            where provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? NSString else { return }
                    let pasted = text as String
                    Task { @MainActor in self.onPaste(pasted) }
                }
                return
            }
        }
    }
}
#endif
