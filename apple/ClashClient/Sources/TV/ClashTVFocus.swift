import SwiftUI

extension View {
     
     
     
     
     
     
    func onClashTVFocus(_ handler: @escaping () -> Void) -> some View {
        modifier(ClashTVFocusReporter(handler: handler))
    }
}

private struct ClashTVFocusReporter: ViewModifier {
    let handler: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, isFocused in
                if isFocused { handler() }
            }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVSwitch<Label: View>: View {
    @Binding var isOn: Bool
    let identifier: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button { isOn.toggle() } label: {
            LabeledContent {
                Text(ClashTVSwitchWord.of(isOn: isOn))
            } label: {
                label()
            }
        }
        .accessibilityRepresentation {
            Toggle(isOn: $isOn, label: label)
                .accessibilityIdentifier(identifier)
        }
    }
}

 
enum ClashTVSwitchWord {
    static func of(isOn: Bool) -> String {
        isOn ? String(localized: "On") : String(localized: "Off")
    }
}
