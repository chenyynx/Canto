import ClashClientUI
import Combine
import Foundation

enum ProfileInstallLinkError: LocalizedError, Equatable {
    case unsupportedLink
    case missingSubscription
    case unusableSubscription
    case unsupportedFile
    case fileTooLarge
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            return "This install link is not supported."
        case .missingSubscription:
            return "The install link does not contain a profile URL."
        case .unusableSubscription:
            return "The install link does not contain a usable profile URL."
        case .unsupportedFile:
            return "That file is not a configuration Clash can read."
        case .fileTooLarge:
             
            return "The configuration file is larger than 128 MB, the most Clash can import."
        case .unreadableFile:
            return "That file is not a text configuration. Choose a different one."
        }
    }
}

extension ImportedFileBytes {
     
     
     
     
     
    static func readForImport(_ url: URL, maximumBytes: Int = ProfileShareInbox.defaultMaximumBytes) throws -> Data {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maximumBytes {
            throw ProfileInstallLinkError.fileTooLarge
        }
        let data = try read(url)
        guard data.count <= maximumBytes else { throw ProfileInstallLinkError.fileTooLarge }
        return data
    }
}

enum ProfileImportRequest: Equatable {
    case subscription(String)
    case configuration(fileName: String, yaml: String)
}

 
 
 
 
 
 
 
 
 
 
struct ProfileImportOutcome: Equatable, Sendable {
    var imported = 0
    var refusals: [ClashDisplayText] = []

    var isEmpty: Bool { imported == 0 && refusals.isEmpty }
}

enum FlClashInstallLink {
     
     
     
     
     
     
     
     
     
     
    private static let schemes: Set<String> = ["clash", "clashmeta", "flclash"]

    static func subscriptionURL(from link: URL) throws -> String {
        guard let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              schemes.contains(scheme),
              components.host?.lowercased() == "install-config" else {
            throw ProfileInstallLinkError.unsupportedLink
        }
        guard let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
              !raw.isEmpty else {
            throw ProfileInstallLinkError.missingSubscription
        }
         
         
         
         
        guard let subscription = URLComponents(string: raw),
              subscription.scheme != nil,
              subscription.host != nil else {
            throw ProfileInstallLinkError.unusableSubscription
        }
        return raw
    }

     
     
     
     
     
     
    static func isLocalOrigin(_ raw: String) -> Bool {
        guard let host = URLComponents(string: raw)?.host?.lowercased() else { return false }
        if host == "localhost" || host == "::1" || host == "[::1]" || host == "0.0.0.0" { return true }
        return host.hasPrefix("127.")
    }
}

@MainActor
final class ProfileImportRouter: ObservableObject {
     
     
     
     
     
     
     
    @Published private(set) var pendingConfirmation: String?
    @Published private(set) var pendingImport: ProfileImportRequest?
    @Published private(set) var errorMessage = ""
     
     
     
     
     
     
     
     
    @Published private(set) var untoldRefusals: [ClashDisplayText] = []
     
     
     
     
     
    @Published private(set) var centresOnScreen: [UUID] = []
     
     
    @Published private(set) var centreAppearances = 0

    func centreAppeared(_ id: UUID) {
        centresOnScreen.removeAll { $0 == id }
        centresOnScreen.append(id)
        centreAppearances &+= 1
    }

    func centreDisappeared(_ id: UUID) {
        centresOnScreen.removeAll { $0 == id }
    }
    private var queue: [ProfileImportRequest] = []
    private let inbox: ProfileShareInbox?
    private let fetchLocalOrigin: (URL) async throws -> Data

    init(
        inbox: ProfileShareInbox? = ProfileShareInbox(),
        fetchLocalOrigin: @escaping (URL) async throws -> Data = { url in
             
             
             
             
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            return try await session.data(for: URLRequest(url: url)).0
        }
    ) {
        self.inbox = inbox
        self.fetchLocalOrigin = fetchLocalOrigin
    }

     
     
     
    @discardableResult
    func open(_ link: URL) -> Task<ProfileImportOutcome, Never>? {
        errorMessage = ""
        ClashLogStore.shared.append(
            "install link arrived  pendingBefore=\(pendingConfirmation != nil)  link=\(link.absoluteString)",
            stream: .app, level: .warning)
        do {
            if link.isFileURL {
                 
                 
                return try importFile(link)
            }
            pendingConfirmation = try FlClashInstallLink.subscriptionURL(from: link)
            return nil
        } catch {
             
             
            return reportInOrder(refusal(error))
        }
    }

    func acceptPendingConfirmation() {
        guard let url = pendingConfirmation else { return }
        ClashLogStore.shared.append("install link accepted  \(url)", stream: .app, level: .warning)
        pendingConfirmation = nil
        guard FlClashInstallLink.isLocalOrigin(url), let local = URL(string: url) else {
            publishInOrder(.subscription(url))
            return
        }
         
        let fileName = local.lastPathComponent.hasSuffix(".yaml")
            || local.lastPathComponent.hasSuffix(".yml")
            ? local.lastPathComponent
            : "\(local.host ?? "local")-import.yaml"
         
         
         
        enqueue { [weak self] in
            guard let self else { return ([], []) }
            do {
                let data = try await self.fetchLocalOrigin(local)
                return ([(try Self.sized(data), fileName)], [])
            } catch {
                return ([], [self.refusal(error)])
            }
        }
    }

    func declinePendingConfirmation() {
        ClashLogStore.shared.append(
            "install link declined  hadPending=\(pendingConfirmation != nil)",
            stream: .app, level: .warning)
        pendingConfirmation = nil
    }

     
     
     
     
     
     
     
     
    nonisolated static func confirmationText(for url: URL) -> String {
        url.absoluteString
    }

    nonisolated static func confirmationText(for raw: String) -> String {
        raw
    }

     
     
     
    nonisolated static func confirmationIsLocalConfiguration(_ raw: String) -> Bool {
        FlClashInstallLink.isLocalOrigin(raw)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func take() -> ProfileImportRequest? {
        if isEmitting {
            guard !takenWhileEmitting, let current = emitting else { return nil }
            takenWhileEmitting = true
            return current
        }
        guard let current = pendingImport else { return nil }
         
         
         
         
         
         
        emit(nil)
        if !queue.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.advanceIfIdle() }
        }
        return current
    }

    private var isEmitting = false
    private var takenWhileEmitting = false
    private var emitting: ProfileImportRequest?

    private func advance() {
        emit(queue.isEmpty ? nil : queue.removeFirst())
    }

    private func advanceIfIdle() {
        guard pendingImport == nil, !isEmitting, !queue.isEmpty else { return }
        advance()
    }

     
     
    private func emit(_ next: ProfileImportRequest?) {
        isEmitting = true
        emitting = next
        pendingImport = next
        isEmitting = false
        emitting = nil
        if takenWhileEmitting {
            takenWhileEmitting = false
            advance()
        }
    }

     
     
     
     
     
     
     
     
    @discardableResult
    func importSharedFiles() -> Task<ProfileImportOutcome, Never>? {
        guard let inbox else { return nil }
        let shared: [SharedProfileFile]
        do {
            shared = try inbox.dequeueAll()
        } catch {
            return reportInOrder(refusal(error))
        }
        guard !shared.isEmpty else { return nil }
        var failures: [Refusal] = []
        var admitted: [(data: Data, fileName: String)] = []
        for file in shared {
            do {
                admitted.append((try Self.sized(file.data), "Shared Configuration.yaml"))
            } catch {
                 
                 
                failures.append(refusal(error))
            }
        }
        return check(admitted, failures: failures)
    }

     
    func dismissRefusals() {
        untoldRefusals = []
    }

    private func importFile(_ url: URL) throws -> Task<ProfileImportOutcome, Never> {
         
         
         
         
         
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > ProfileShareInbox.defaultMaximumBytes {
            throw ProfileInstallLinkError.fileTooLarge
        }
        return check([(try Self.sized(ImportedFileBytes.read(url)), url.lastPathComponent)])
    }

     
    nonisolated static func sized(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= ProfileShareInbox.defaultMaximumBytes else {
            throw data.isEmpty
                ? ProfileInstallLinkError.unreadableFile
                : ProfileInstallLinkError.fileTooLarge
        }
        return data
    }

     
     
     
    nonisolated static func text(of data: Data) throws -> String {


        guard let yaml = String(data: data, encoding: .utf8) else {
            throw ProfileInstallLinkError.unreadableFile
        }
        return yaml
    }



     
     
     
     
    private func check(_ items: [(data: Data, fileName: String)],
                       failures: [Refusal] = []) -> Task<ProfileImportOutcome, Never> {
        enqueue { (items, failures) }
    }

     
     
     
    private struct Refusal: Sendable {
        let sentence: String
        let text: ClashDisplayText
    }

     
     
     
     
    @discardableResult
    private func enqueue(_ produce: @escaping @MainActor () async
                            -> (items: [(data: Data, fileName: String)], failures: [Refusal]))
        -> Task<ProfileImportOutcome, Never> {
        let previous = checking
        checkingGeneration &+= 1
        let generation = checkingGeneration
        let run = Task { @MainActor [weak self] () -> ProfileImportOutcome in
            _ = await previous?.value
            let (items, failures) = await produce()
            let verdicts = await Task.detached(priority: .userInitiated) { () -> [Result<String, Error>] in
                items.map { item in
                    Result {
                        let yaml = try ProfileImportRouter.text(of: item.data)
                        try ConfigTransforms.validateSource(yaml)
                        AppCore.returnFreeMemoryNow(after: yaml)
                        return yaml
                    }
                }
            }.value
            guard let self else { return ProfileImportOutcome() }
            var told = failures
            var imported = 0
            for (item, verdict) in zip(items, verdicts) {
                switch verdict {
                case .failure(let error):
                    told.append(self.refusal(error))
                case .success(let yaml):
                    self.publish(.configuration(fileName: item.fileName, yaml: yaml))
                    imported += 1
                }
            }
            self.errorMessage = told.map(\.sentence).joined(separator: "\n")
            self.untoldRefusals += told.map(\.text)
            if self.checkingGeneration == generation { self.checking = nil }
            return ProfileImportOutcome(imported: imported, refusals: told.map(\.text))
        }
        checking = run
        return run
    }

     
     
    private func reportInOrder(_ refusal: Refusal) -> Task<ProfileImportOutcome, Never> {
        guard checking != nil else {
            errorMessage = refusal.sentence
            untoldRefusals.append(refusal.text)
            return Task { ProfileImportOutcome(refusals: [refusal.text]) }
        }
        return enqueue { ([], [refusal]) }
    }

     
     
    private func publishInOrder(_ request: ProfileImportRequest) {
        guard let previous = checking else {
            publish(request)
            return
        }
        checkingGeneration &+= 1
        let generation = checkingGeneration
        checking = Task { @MainActor [weak self] () -> ProfileImportOutcome in
            _ = await previous.value
            guard let self else { return ProfileImportOutcome() }
            self.publish(request)
            if self.checkingGeneration == generation { self.checking = nil }
            return ProfileImportOutcome(imported: 1)
        }
    }

    private var checking: Task<ProfileImportOutcome, Never>?
    private var checkingGeneration = 0

     
     
    func waitForImports() async {
        while let running = checking {
            _ = await running.value
        }
    }

    private func publish(_ request: ProfileImportRequest) {
        if pendingImport == nil, !isEmitting {
            emit(request)
        } else {
            queue.append(request)
        }
        errorMessage = ""
    }

    private func refusal(_ error: Error) -> Refusal {
        if let install = error as? ProfileInstallLinkError {
            return Refusal(sentence: install.localizedDescription,
                           text: .copy(install.errorDescription ?? install.localizedDescription))
        }
        if let failure = ConfigurationFailureClassifier.classify(
            error,
            context: .localImport,
            preservesLastKnownGood: false
        ) {
            return Refusal(sentence: failure.localizedDescription, text: failure.displayMessage)
        }
        let sentence = "The profile could not be imported."
        return Refusal(sentence: sentence, text: .copy(sentence))
    }
}
