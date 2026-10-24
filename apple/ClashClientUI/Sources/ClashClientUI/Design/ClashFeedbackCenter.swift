import Foundation
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashFeedbackCenter: ObservableObject {
    @Published public private(set) var state = ClashFeedbackCenterState()
     
     
    @Published public private(set) var claimed: [String: Int] = [:]

    public let lifetime: ClashFeedbackLifetime
     
     
    public var locale: Locale = .current
     
     
    public var currentScreen: String?

    private var handlers: [Int: () -> Void] = [:]
     
     
    private var dismissals: [Int: () -> Void] = [:]
    private var timer: Task<Void, Never>?
    private var pauses: Set<String> = []
     
    var headers: [UUID: CGRect] = [:]
     
     
     
     
    public var headersDidChange: (() -> Void)?
     
     
     
     
    @Published public private(set) var headerRoom: CGFloat = 0
    private let clock: () -> Date
    private let announce: (String) -> Void

    public init(
        lifetime: ClashFeedbackLifetime,
        clock: @escaping () -> Date = Date.init,
        announce: @escaping (String) -> Void
    ) {
        self.lifetime = lifetime
        self.clock = clock
        self.announce = announce
    }

     

     
     
    @discardableResult
    public func show(
        _ presentation: ClashFeedbackPresentation,
        operation: String? = nil,
        perform: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> Int {
        let id = state.show(presentation, screen: currentScreen, operation: operation,
                            characters: spoken(presentation).count, now: clock(), lifetime: lifetime)
        if presentation.action != nil, let perform { handlers[id] = perform }
        if let onDismiss { dismissals[id] = onDismiss }
        settle(announcing: presentation)
        return id
    }

     
    @discardableResult
    public func update(
        _ id: Int,
        to presentation: ClashFeedbackPresentation,
        perform: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> Bool {
        guard state.update(id, to: presentation, screen: currentScreen,
                           characters: spoken(presentation).count, now: clock(), lifetime: lifetime)
        else { return false }
         
        handlers[id] = presentation.action != nil ? perform : nil
        if let onDismiss { dismissals[id] = onDismiss }
        settle(announcing: presentation)
        return true
    }

     
     
     
    @discardableResult
    public func answer(
        _ id: Int?,
        with presentation: ClashFeedbackPresentation,
        operation: String? = nil,
        perform: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> Int {
        if let id, update(id, to: presentation, perform: perform, onDismiss: onDismiss) { return id }
        return show(presentation, operation: operation, perform: perform, onDismiss: onDismiss)
    }

     
     
     
     
    public func dismiss(operation: String) {
        for entry in [state.current, state.covered].compactMap({ $0 }) where entry.operation == operation {
            dismiss(entry.id)
        }
    }

     
     
    public func run(
        operation: String,
        progress: ClashFeedbackPresentation?,
        _ work: @MainActor () async -> ClashFeedbackPresentation?
    ) async {
        let id = progress.map { show($0, operation: operation) }
        let result = await work()
        switch (id, result) {
        case let (_, result?): answer(id, with: result, operation: operation)
        case let (id?, nil): dismiss(id)
        case (nil, nil): break
        }
    }

     
    public func dismiss(_ id: Int) {
        let told = dismissals[id]
        state.dismiss(id, now: clock())
        settle(announcing: nil)
        told?()
    }

     
     
    public func clear() {
        state.clear()
        settle(announcing: nil)
    }

     
     
     
     
    public func perform(_ id: Int) {
        guard let handler = handlers[id] else { return }
        dismissals[id] = nil
        dismiss(id)
        handler()
    }

     
    public func offersAction(_ id: Int) -> Bool {
        handlers[id] != nil
    }

     
    public func result(for operation: String) -> ClashFeedbackCenterState.ShownResult? {
        guard let entry = state.current, entry.operation == operation else { return nil }
        return entry
    }

     
    public var unclaimed: ClashFeedbackCenterState.ShownResult? {
        guard let entry = state.current else { return nil }
        if let operation = entry.operation, claimed[operation, default: 0] > 0 { return nil }
        return entry
    }

     

    public func claim(_ operations: [String]) {
        for operation in operations { claimed[operation, default: 0] += 1 }
    }

    public func release(_ operations: [String]) {
        for operation in operations {
            let count = claimed[operation, default: 0] - 1
            claimed[operation] = count > 0 ? count : nil
        }
    }

     

     
     
    public func pause(_ reason: String) {
        guard pauses.insert(reason).inserted, pauses.count == 1 else { return }
        state.pause(now: clock())
        reschedule()
    }

    public func resume(_ reason: String) {
        guard pauses.remove(reason) != nil, pauses.isEmpty else { return }
        state.resume(now: clock())
        reschedule()
    }

     
    public func dropTransient() {
        state.dropTransient(now: clock())
        settle(announcing: nil)
    }

     
    public func leaveScreen(_ screen: String) {
        state.leaveScreen(screen)
        settle(announcing: nil)
    }

     

    private func settle(announcing presentation: ClashFeedbackPresentation?) {
        let live = Set([state.current?.id, state.covered?.id].compactMap { $0 })
        handlers = handlers.filter { live.contains($0.key) }
        dismissals = dismissals.filter { live.contains($0.key) }
        if let presentation, presentation.kind != .loading { announce(spoken(presentation)) }
        reschedule()
    }

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard let deadline = state.current?.deadline else { return }
        let delay = max(0, deadline.timeIntervalSince(clock()))
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

     
    func fire() {
        if state.expire(now: clock()) { settle(announcing: nil) } else { reschedule() }
    }

     
    public func spoken(_ presentation: ClashFeedbackPresentation) -> String {
        [presentation.title.resolved(locale: locale), presentation.message?.resolved(locale: locale)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

private struct ClashFeedbackCenterKey: EnvironmentKey {
    static let defaultValue: ClashFeedbackCenter? = nil
}

public extension EnvironmentValues {
     
     
    var clashFeedback: ClashFeedbackCenter? {
        get { self[ClashFeedbackCenterKey.self] }
        set { self[ClashFeedbackCenterKey.self] = newValue }
    }
}

private struct ClashFeedbackClaimModifier: ViewModifier {
    @Environment(\.clashFeedback) private var center
    let operations: [String]

    func body(content: Content) -> some View {
        content
            .onAppear { center?.claim(operations) }
            .onDisappear { center?.release(operations) }
    }
}

public extension View {
     
    func clashFeedbackClaim(_ operations: [String]) -> some View {
        modifier(ClashFeedbackClaimModifier(operations: operations))
    }
}

 
 
 
 
extension ClashFeedbackCenter {
     
     
    public var lowestHeader: CGRect? { headers.values.max { $0.maxY < $1.maxY } }

    func setHeader(_ id: UUID, _ frame: CGRect?) {
        guard headers[id] != frame else { return }
        headers[id] = frame
        headersDidChange?()
    }

     
     
    public static func headerRoom(barHeight: CGFloat?, underHeader: Bool) -> CGFloat {
        guard underHeader, let barHeight, barHeight > 0 else { return 0 }
        return barHeight + headerBarGap
    }

     
    public static let headerBarGap: CGFloat = 6

     
    public func setHeaderRoom(_ height: CGFloat) {
        guard headerRoom != height else { return }
        headerRoom = height
    }
}

private struct ClashFeedbackBarBelowModifier: ViewModifier {
    @Environment(\.clashFeedback) private var center
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { center?.setHeader(id, proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { center?.setHeader(id, $0) }
            })
            .onDisappear { center?.setHeader(id, nil) }
    }
}

public extension View {
     
    func clashFeedbackBarBelow() -> some View {
        modifier(ClashFeedbackBarBelowModifier())
    }
}

 
 
public struct ClashFeedbackHeaderRoom: View {
    @Environment(\.clashFeedback) private var center

    public init() {}

    public var body: some View {
        if let center { Room(center: center) }
    }

    private struct Room: View {
        @ObservedObject var center: ClashFeedbackCenter

        var body: some View {
            Color.clear
                .frame(height: center.headerRoom)
                .accessibilityHidden(true)
        }
    }
}
