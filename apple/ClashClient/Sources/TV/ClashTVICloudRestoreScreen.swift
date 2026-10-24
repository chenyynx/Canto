import ClashClientKit
import SwiftUI

 
 
enum ClashTVICloudRestorePresentation {
     
    static func welcomeLine(_ availability: ClashTVICloudRestore.Availability) -> String? {
        if case .ready = availability { return String(localized: "Restore from iCloud") }
        return nil
    }

    static func itemLine(_ item: ClashTVICloudRestore.Plan.Item) -> String {
        switch item.disposition {
        case .restorable(true):
            String(localized: "Ready to restore")
        case .restorable(false):
            String(localized: "Overrides not applied — back up again on your iPhone")
        case .skippedLocalResources(let count):
            String(localized: "Uses \(count) local resource files — not supported on Apple TV yet")
        }
    }

    static func rowSubtitle(_ restored: ClashTVSubscription.Restored) -> String {
        let when = restored.exportedAt.formatted(.relative(presentation: .named))
        return String(localized: "From iCloud · \(restored.sourceDevice) · \(when)")
    }

    static func sourceChoice(_ summary: BackupRecordSummary) -> String {
        let device = summary.sourceDevice ?? summary.installID
        let when = summary.exportedAt?.formatted(.relative(presentation: .named)) ?? ""
        return "\(device) · \(when)"
    }
}

 
 
 
 
 
 
struct ClashTVICloudRestoreScreen: View {
    @Binding var state: ClashTVProductState
     
    let service: ClashTVICloudRestore?
    @Binding var store: ClashTVSubscriptionStore
     
     
    var onDone: () -> Void = {}

    @State private var availability: ClashTVICloudRestore.Availability?
    @State private var plan: ClashTVICloudRestore.Plan?
    @State private var failure: String?

    var body: some View {
        List {
            switch availability {
            case nil:
                Text("Downloading from iCloud…")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("Sign in to iCloud on this Apple TV to restore from your iPhone.")
            case .noBackups:
                Text("Nothing to restore yet. On your iPhone or Mac, open Clash, go to Backup & Restore, and turn on “Sync Profiles to Apple TV”.")
            case .failed(let sentence):
                 
                Text(verbatim: sentence)
            case .ready(let backups):
                if backups.count > 1, plan == nil {
                    Section("Choose the device to restore from") {
                        ForEach(backups) { summary in
                            Button(ClashTVICloudRestorePresentation.sourceChoice(summary)) {
                                state.beginOperation()
                                Task { await load(summary) }
                            }
                        }
                    }
                }
                if let plan {
                     
                     
                     
                    Section(ClashTVICloudRestorePresentation.sourceChoice(plan.summary)) {
                        Button("Restore \(plan.restorableCount) profiles") { apply(plan) }
                            .disabled(plan.restorableCount == 0)
                            .accessibilityIdentifier("tvos.icloud.restore")
                    }
                    Section {
                        ForEach(plan.items) { item in
                            LabeledContent(item.label, value: ClashTVICloudRestorePresentation.itemLine(item))
                                .accessibilityIdentifier("tvos.icloud.item.\(item.id)")
                        }
                    }
                }
            }
            if let failure {
                 
                Text(verbatim: failure)
                    .foregroundStyle(.red)
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Restore from iCloud")
        .task { await refreshAvailability() }
    }

    private func refreshAvailability() async {
        guard let service else {
            availability = .unavailable
            return
        }
        var availability = await ClashTVICloudRestore.availability(locator: service.locator())
         
         
        var retries = 2
        while case .noBackups = availability, retries > 0 {
            retries -= 1
             
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            availability = await ClashTVICloudRestore.availability(locator: service.locator())
        }
        self.availability = availability
         
        if case .failed(let sentence) = availability, !Task.isCancelled {
            state.post(ClashTVFeedback.couldNotRestore(reason: sentence), for: .restore)
        }
        if case .ready(let backups) = availability, backups.count == 1 { await load(backups[0]) }
    }

    private func load(_ summary: BackupRecordSummary) async {
        guard let service, let locator = service.locator() else { return }
        do {
            failure = nil
            plan = ClashTVICloudRestore.plan(summary: summary, envelope: try await locator.read(summary))
        } catch {
             
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            failure = error.localizedDescription
             
            state.post(ClashTVFeedback.couldNotRestore(reason: error.localizedDescription), for: .restore)
        }
    }

    private func apply(_ plan: ClashTVICloudRestore.Plan) {
        guard let service else { return }
        state.beginOperation()
        do {
            let outcome = try service.apply(plan, to: &store)
             
             
             
            state.post(ClashTVFeedback.restored(count: outcome.restored.count), for: .restore)
            onDone()
        } catch {
            failure = error.localizedDescription
            state.post(ClashTVFeedback.couldNotRestore(reason: error.localizedDescription), for: .restore)
        }
    }
}
