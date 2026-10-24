import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashMacProfilesList: View {
    let profiles: [ClashProfileSnapshot]
     
     
    let selectingProfileID: Profile.ID?
    let selectionFailure: (Profile.ID) -> ClashDisplayText?
    let select: (Profile.ID) -> Void
    let openDetail: (Profile.ID) -> Void
    let reorder: ([Profile.ID]) -> Void
    let addProfile: () -> Void
     
     
     
     
     
     
     
     
     
    let backupDestination: (() -> AnyView)?
    let sync: (Profile.ID) -> Void
    let duplicate: (Profile.ID) -> Void
    let export: (Profile.ID) -> Void
    let delete: (Profile.ID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingDeletion: ClashProfileSnapshot?
    @State private var showsBackup = false
     
     
     
     
     
    @State private var utcDay = Date()

    public init(
        profiles: [ClashProfileSnapshot],
        selectingProfileID: Profile.ID?,
        selectionFailure: @escaping (Profile.ID) -> ClashDisplayText?,
        select: @escaping (Profile.ID) -> Void,
        openDetail: @escaping (Profile.ID) -> Void,
        reorder: @escaping ([Profile.ID]) -> Void,
        addProfile: @escaping () -> Void,
        backupDestination: (() -> AnyView)? = nil,
        sync: @escaping (Profile.ID) -> Void,
        duplicate: @escaping (Profile.ID) -> Void,
        export: @escaping (Profile.ID) -> Void,
        delete: @escaping (Profile.ID) -> Void
    ) {
        self.profiles = profiles
        self.selectingProfileID = selectingProfileID
        self.selectionFailure = selectionFailure
        self.select = select
        self.openDetail = openDetail
        self.reorder = reorder
        self.addProfile = addProfile
        self.backupDestination = backupDestination
        self.sync = sync
        self.duplicate = duplicate
        self.export = export
        self.delete = delete
    }

    public var body: some View {
        List {
             
             
             
             
             
             
             
             
             
            Section {
                 
                 
                 
                 
                 
                 
                 
                ForEach(Array(profiles.enumerated()), id: \.element.id) {
                    index, profile in
                    row(profile)
                         
                         
                         
                         
                        .listRowSeparator(
                            index == profiles.count - 1 ? .hidden : .automatic,
                            edges: .bottom
                        )
                }
            }

            Section {
                addRow

                if let backupDestination {
                    backupRow(backupDestination)
                }
            }
        }
        .listStyle(.inset)
         
         
         
         
         
        .clashProductModal(
            isPresented: $showsBackup,
            role: .form,
            macOSPanelRole: .page
        ) {
            backupDestination?() ?? AnyView(EmptyView())
        }
        .alert(
            Text(clash: .copy("Delete Profile")),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { profile in
            Button(role: .destructive) {
                delete(profile.id)
                pendingDeletion = nil
            } label: {
                Text(clash: .copy("Delete"))
            }
            Button(role: .cancel) {
                pendingDeletion = nil
            } label: {
                Text(clash: .copy("Cancel"))
            }
        } message: { profile in
             
             
            Text(verbatim: profile.label)
        }
        .task {
             
             
             
            while !Task.isCancelled {
                let now = Date()
                let next = Self.expiryCalendar.nextDate(
                    after: now,
                    matching: DateComponents(hour: 0, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) ?? now.addingTimeInterval(86_400)
                try? await Task.sleep(
                    for: .seconds(next.timeIntervalSince(now) + 1)
                )
                guard !Task.isCancelled else { return }
                utcDay = Date()
            }
        }
         
         
         
         
        .clashPageProbe("profiles-list")
         
         
         
         
        .clashFrameWatch("profiles-list")
    }

     
     
     
     
     
     
     
     
    private func row(_ profile: ClashProfileSnapshot) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Button {
                select(profile.id)
            } label: {
                HStack(spacing: ClashTheme.Spacing.compact) {
                     
                     
                     
                     
                     
                    statusSlot(profile)

                    VStack(alignment: .leading, spacing: 1) {
                         
                         
                         
                         
                        HStack(
                            alignment: .firstTextBaseline,
                            spacing: ClashTheme.Spacing.compact
                        ) {
                            Text(verbatim: profile.label)
                                .fontWeight(
                                    profile.isCurrent ? .semibold : .regular
                                )
                            if let fraction =
                                profile.subscription?.usageFraction,
                                !dynamicTypeSize.isAccessibilitySize {
                                Spacer(minLength: ClashTheme.Spacing.compact)
                                 
                                 
                                 
                                 
                                 
                                Text(clash: .format(
                                    "%@ used",
                                    ["\(Int(fraction * 100))%"]
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            }
                        }
                        Text(clash: profile.sourceSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let subscription = profile.subscription,
                           let fraction = subscription.usageFraction {
                            usageGauge(fraction: fraction)
                                .padding(.top, 3)
                            if dynamicTypeSize.isAccessibilitySize {
                                 
                                 
                                 
                                 
                                accessibilityUsageSummary(subscription)
                                    .padding(.top, 1)
                            } else if let expiration =
                                subscription.expiration {
                                Text(clash: .format(
                                    "until %@",
                                    [Self.expiryDateString(expiration)]
                                ))
                                .font(.caption)
                                .foregroundColor(
                                    expiryTint(expiration, now: utcDay)
                                )
                                .monospacedDigit()
                                .lineLimit(1)
                                .padding(.top, 1)
                            }
                        }
                         
                         
                        if let failure = selectionFailure(profile.id) {
                            Text(clash: failure)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier(
                                    "profiles.select-failure"
                                )
                        }
                    }

                    Spacer(minLength: ClashTheme.Spacing.row)
                }
                 
                 
                 
                 
                 
                 
                 
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
             
             
             
             
            .disabled(isBlocked(profile))
            .accessibilityIdentifier("profiles.row.\(profile.id.rawValue)")

            if profile.isBusy {
                ProgressView().controlSize(.small)
            }

             
             
             
             
             
             
             
             
             
            Button {
                openDetail(profile.id)
            } label: {
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.secondary)
                    .frame(width: ClashTheme.Control.pointerRowTarget)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(clash: .copy("Profile")))
            .accessibilityIdentifier("profiles.detail.\(profile.id.rawValue)")
        }
        .padding(.vertical, 2)
        .contextMenu {
             
             
             
            Button {
                move(profile.id, by: -1)
            } label: {
                Text(clash: .copy("Move Up"))
            }
            .disabled(ClashMacProfilesList.reordered(profiles, moving: profile.id, by: -1) == nil)

            Button {
                move(profile.id, by: 1)
            } label: {
                Text(clash: .copy("Move Down"))
            }
            .disabled(ClashMacProfilesList.reordered(profiles, moving: profile.id, by: 1) == nil)

            Divider()

            Button { sync(profile.id) } label: {
                Text(clash: .copy("Sync"))
            }
            Button { duplicate(profile.id) } label: {
                Text(clash: .copy("Duplicate"))
            }
            Button { export(profile.id) } label: {
                Text(clash: .copy("Export"))
            }
            if profile.canDelete {
                Divider()
                Button(role: .destructive) {
                    pendingDeletion = profile
                } label: {
                    Text(clash: .copy("Delete"))
                }
            }
        }
    }

     
     
    @ViewBuilder
    private func statusSlot(_ profile: ClashProfileSnapshot) -> some View {
        ZStack {
            if selectingProfileID == profile.id {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .opacity(profile.isCurrent ? 1 : 0)
            }
        }
        .frame(width: 16)
    }

    private func isBlocked(_ profile: ClashProfileSnapshot) -> Bool {
        selectingProfileID != nil && selectingProfileID != profile.id
    }

     

     
     
     
     
     
     
     
     
     
     
    private func usageGauge(fraction: Double) -> some View {
        let clamped = min(max(fraction, 0), 1)
        let fill: Color = fraction >= 1 ? .red : .accentColor
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(fill.opacity(0.22))
                Capsule()
                    .fill(fill)
                     
                     
                    .frame(width: max(
                        6, proxy.size.width * CGFloat(clamped)
                    ))
            }
        }
        .frame(height: 6)
        .accessibilityLabel(Text(clash: .copy("Data Usage")))
        .accessibilityValue(Text(clash: .format(
            "%@ percent", ["\(Int(fraction * 100))"]
        )))
    }

     
     
     
     
     
    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
            ?? TimeZone(secondsFromGMT: 0)!
        return formatter
    }()

    private static let expiryCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")
            ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func expiryDateString(_ date: Date) -> String {
        expiryFormatter.string(from: date)
    }

     
     
     
     
     
     
    private func accessibilityUsageSummary(
        _ subscription: ClashProfileSubscriptionSnapshot
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.tight
        ) {
            Text(
                "Uploaded \(Self.compactBytes(subscription.uploadBytes))"
            )
            Text(
                "Downloaded \(Self.compactBytes(subscription.downloadBytes))"
            )
            if subscription.totalBytes > 0 {
                Text(
                    "Total \(Self.compactBytes(subscription.totalBytes))"
                )
            }
            if let expiration = subscription.expiration {
                Text("Expires \(Self.expiryDateString(expiration))")
                    .foregroundStyle(expiryTint(expiration, now: utcDay))
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }

     
    private static func compactBytes(_ bytes: Int64) -> String {
        let units = ["K", "M", "G", "T"]
        var value = Double(max(0, bytes)) / 1_024
        var unit = 0
        while value >= 1_000, unit < units.count - 1 {
            value /= 1_024
            unit += 1
        }
        let text = value < 100
            ? String(format: "%.1f", value)
            : String(format: "%.0f", value)
        return text.replacingOccurrences(
            of: ".0",
            with: ""
        ) + units[unit]
    }

     
     
     
     
    private func expiryTint(_ expiration: Date, now: Date) -> Color {
        let days =
            Self.expiryCalendar.dateComponents(
                [.day],
                from: Self.expiryCalendar.startOfDay(for: now),
                to: Self.expiryCalendar.startOfDay(for: expiration)
            ).day ?? 0
        if days <= 0 { return .red }
        if days <= 7 { return .orange }
        return .secondary
    }

    private func move(_ id: Profile.ID, by offset: Int) {
        guard let ordered = Self.reordered(profiles, moving: id, by: offset) else {
            return
        }
        reorder(ordered)
    }

     
     
     
     
     
     
     
    static func reordered(
        _ profiles: [ClashProfileSnapshot],
        moving id: Profile.ID,
        by offset: Int
    ) -> [Profile.ID]? {
        guard let from = profiles.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let to = from + offset
        guard profiles.indices.contains(to) else { return nil }
        var ordered = profiles
        ordered.swapAt(from, to)
        return ordered.map(\.id)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     

     
     
     
     
     
     
    private func actionRow(
        symbol: String,
        title: ClashDisplayText,
        subtitle: ClashDisplayText,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(clash: title)
                Text(clash: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: ClashTheme.Spacing.row)

             
             
             
            Image(systemName: "chevron.forward")
                .foregroundStyle(.secondary)
                .opacity(showsChevron ? 1 : 0)
                .frame(width: ClashTheme.Control.pointerRowTarget)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var addRow: some View {
        Button(action: addProfile) {
            actionRow(
                symbol: ClashSymbol.plusCircle.rawValue,
                title: .copy("Add Profile"),
                subtitle: .copy("Profile URL · YAML file · from scratch"),
                showsChevron: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profiles.add")
        .padding(.vertical, 2)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private func backupRow(_ destination: @escaping () -> AnyView) -> some View {
        Button {
            showsBackup = true
        } label: {
            actionRow(
                symbol: ClashSymbol.arrowClockwiseIcloud.rawValue,
                title: .copy("Backup & Restore"),
                subtitle: .copy("Everything a profile needs to run"),
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profiles.backup")
        .padding(.vertical, 2)
    }
}
