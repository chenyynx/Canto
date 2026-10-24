import SwiftUI

 
 
 
@MainActor
final class ClashRootDepartureGuard: ObservableObject {
    private struct Registration {
         
         
         
         
         
         
         
        let id: UUID
        let isDirty: Bool
        let isBusy: Bool
        let save: (@escaping (Bool) -> Void) -> Void
        let discard: () -> Void
    }

    @Published private(set) var isPromptPresented = false
    @Published private(set) var isBusy = false

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var registrations: [Registration] = []
    private var registration: Registration? { registrations.last }
     
     
    var hasDirtyRegistration: Bool { registration?.isDirty == true }
    private var pendingDeparture: (() -> Void)?
    private var isSaving = false

    func register(
        id: UUID,
        isDirty: Bool,
        isBusy: Bool,
        save: @escaping (@escaping (Bool) -> Void) -> Void,
        discard: @escaping () -> Void
    ) {
        let entry = Registration(
            id: id,
            isDirty: isDirty,
            isBusy: isBusy,
            save: save,
            discard: discard
        )
        let wasDirty = hasDirtyRegistration
        if let existing = registrations.firstIndex(where: { $0.id == id }) {
            registrations[existing] = entry
        } else {
            registrations.append(entry)
        }
        if wasDirty != hasDirtyRegistration {
            dirtyRegistrationDidChange?()
        }
        refreshBusyState()
    }

    private func refreshBusyState() {
         
         
         
         
         
         
        let next = isSaving || registration?.isBusy == true
        if isBusy != next { isBusy = next }
    }

     
     
     
     
     
     
     
     
     
     
    func unregister(id: UUID) {
        let wasDirty = hasDirtyRegistration
        registrations.removeAll { $0.id == id }
        refreshBusyState()
        if wasDirty != hasDirtyRegistration {
            dirtyRegistrationDidChange?()
        }
    }

     
     
     
     
     
    var dirtyRegistrationDidChange: (() -> Void)?

    func requestDeparture(_ departure: @escaping () -> Void) {
        guard let registration else {
            departure()
            return
        }
        guard !isBusy else { return }
        guard registration.isDirty else {
             
             
             
             
             
             
             
            registrations.removeLast()
            refreshBusyState()
            departure()
            return
        }
        pendingDeparture = departure
        isPromptPresented = true
    }

    func saveAndLeave() {
        guard let registration, pendingDeparture != nil else { return }
        isPromptPresented = false
         
         
         
         
        isSaving = true
        refreshBusyState()
        registration.save { [weak self] succeeded in
            guard let self else { return }
            isSaving = false
            guard succeeded else {
                pendingDeparture = nil
                refreshBusyState()
                return
            }
            let departure = pendingDeparture
            pendingDeparture = nil
            registrations.removeAll()
            refreshBusyState()
            departure?()
        }
    }

    func discardAndLeave() {
        guard let registration else { return }
        isPromptPresented = false
        let departure = pendingDeparture
        pendingDeparture = nil
        registration.discard()
        clearRegistration()
        departure?()
    }

    func keepEditing() {
        isPromptPresented = false
        pendingDeparture = nil
    }

     
     
     
    private func clearRegistration() {
        registrations.removeAll()
        isSaving = false
        refreshBusyState()
        isPromptPresented = false
    }
}

private struct ClashRootDepartureGuardKey: EnvironmentKey {
    static let defaultValue: ClashRootDepartureGuard? = nil
}

extension EnvironmentValues {
    var clashRootDepartureGuard: ClashRootDepartureGuard? {
        get { self[ClashRootDepartureGuardKey.self] }
        set { self[ClashRootDepartureGuardKey.self] = newValue }
    }
}

 
 
 
 
 
 
 
 
 
 
 
enum ClashDeparture {
    @MainActor
    static func request(
        _ departureGuard: ClashRootDepartureGuard?,
        leave: @escaping () -> Void
    ) {
        guard let departureGuard else {
            leave()
            return
        }
        departureGuard.requestDeparture(leave)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
public extension View {
    func clashRegistersDeparture(
        isDirty: Bool,
        isBusy: Bool = false,
        save: @escaping (@escaping (Bool) -> Void) -> Void,
        discard: @escaping () -> Void
    ) -> some View {
        modifier(
            ClashDepartureRegistration(
                isDirty: isDirty,
                isBusy: isBusy,
                save: save,
                discard: discard
            )
        )
    }
}

private struct ClashDepartureRegistration: ViewModifier {
     
     
     
     
     
    @State private var id = UUID()
    @Environment(\.clashRootDepartureGuard) private var guardObject
    let isDirty: Bool
    let isBusy: Bool
    let save: (@escaping (Bool) -> Void) -> Void
    let discard: () -> Void

    func body(content: Content) -> some View {
         
         
         
         
         
         
         
         
         
         
         
        register()
        return content
            .onAppear { register() }
             
             
             
             
            .onDisappear { guardObject?.unregister(id: id) }
    }

    private func register() {
        guardObject?.register(
            id: id,
            isDirty: isDirty,
            isBusy: isBusy,
            save: save,
            discard: discard
        )
    }
}
