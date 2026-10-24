import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
struct ClashMacProfilePicker: View {
    let profiles: [ClashProfileSnapshot]
    let select: (Profile.ID) -> Void

     
     
    private enum Metrics {
        static let rowHeight: CGFloat = 24
        static let horizontalInset: CGFloat = ClashTheme.Spacing.row
        static let checkmarkColumn: CGFloat = 16
        static let minimumWidth: CGFloat = 200
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(clash: "Profiles")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, Metrics.horizontalInset)
                .padding(.top, ClashTheme.Spacing.row)
                .padding(.bottom, ClashTheme.Spacing.compact)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(profiles, id: \.id) { profile in
                    row(for: profile)
                }
            }
            .padding(.vertical, ClashTheme.Spacing.tight)

        }
        .frame(minWidth: Metrics.minimumWidth, alignment: .leading)
        .fixedSize()
    }

    private func row(for profile: ClashProfileSnapshot) -> some View {
        Button {
            select(profile.id)
        } label: {
            HStack(spacing: ClashTheme.Spacing.compact) {
                 
                 
                 
                 
                 
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .opacity(profile.isCurrent ? 1 : 0)
                    .frame(width: Metrics.checkmarkColumn, alignment: .leading)
                 
                Text(verbatim: profile.label)
                Spacer(minLength: ClashTheme.Spacing.row)
                if profile.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Metrics.horizontalInset)
            .frame(height: Metrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ClashMacMenuRowButtonStyle())
        .disabled(profile.isBusy)
    }
}

 
 
private struct ClashMacMenuRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovering ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: ClashTheme.Radius.control - 3)
                    .fill(Color.accentColor)
                    .opacity(isHovering ? 1 : 0)
                    .padding(.horizontal, ClashTheme.Spacing.tight)
            )
            .onHover { isHovering = $0 }
    }
}
