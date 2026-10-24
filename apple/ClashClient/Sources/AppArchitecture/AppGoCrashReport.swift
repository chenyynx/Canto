import Foundation

 
 
 
 
enum AppGoCrashReport {
    struct Content: Equatable, Sendable {
        let text: String

        private static let recoveredMarker = "recovered panic in "

        init(text: String) { self.text = text }

         
        init?(nonEmpty text: String) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            self.init(text: text)
        }

         
         
         
        var appQuit: Bool {
            let head = text.range(of: Self.recoveredMarker).map { text[..<$0.lowerBound] } ?? Substring(text)
            return !head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var recoveredPanics: Int { text.components(separatedBy: Self.recoveredMarker).count - 1 }
    }

     
     
    static func consume() -> Content? {
        guard AppCoreSetup.ensureForReaders() else { return nil }
        var error: NSError?
        guard let box = AppCore.consumeGoCrashReport(&error) else { return nil }
        return Content(nonEmpty: box.value)
    }
}

 
@MainActor
final class AppGoCrashReportStore: ObservableObject {
    static let shared = AppGoCrashReportStore()
    @Published private(set) var content: AppGoCrashReport.Content?
    private var consumed = false

    func consumeOnce() {
        guard !consumed else { return }
        consumed = true
        Task {
            content = await Task.detached(priority: .utility) { AppGoCrashReport.consume() }.value
        }
    }
}
