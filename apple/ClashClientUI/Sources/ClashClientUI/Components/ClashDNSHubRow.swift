import SwiftUI

struct ClashDNSHubRow: View {
    let title: String
    let detail: String
    let value: String?
     
     
     
     
    var inlineDetail = false

    var body: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
             
             
            ClashMacNavigationRowLabel(
                .copy(title),
                subtitle: inlineDetail && !detail.isEmpty
                    ? .copy(detail) : nil,
                value: value.map { .copy($0) }
            )
        } else {
            legacyBody
        }
    }

    @ViewBuilder
    private var legacyBody: some View {
#if os(macOS)
         
         
         
         
        HStack(
            alignment: .center,
            spacing: ClashTheme.Spacing.row
        ) {
            Text(clash: .copy(title))
            Spacer(minLength: ClashTheme.Spacing.compact)
            if let value {
                Text(clash: .copy(value))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6.5)
#else
        HStack(
            alignment: .center,
            spacing: ClashTheme.Spacing.row
        ) {
            VStack(alignment: .leading, spacing: 2) {
                 
                 
                 
                 
                 
                 
                Text(clash: .copy(title))
                if !detail.isEmpty {
                    Text(clash: .copy(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
            }
            Spacer(minLength: ClashTheme.Spacing.compact)
            if let value {
                Text(clash: .copy(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
#endif
    }
}
