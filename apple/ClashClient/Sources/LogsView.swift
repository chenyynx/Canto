import ClashClientUI
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers

 
 
 
 
 
 
 
 
 
 
#if os(macOS)
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum MacSavePanel {
     
     
     
     
     
     
     
     
     
     
     
     
    static func write(
        suggestedName: String,
        writing body: @escaping @Sendable (URL) -> Bool,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                 
                 
                 
                guard body(destination) else {
                    Task { @MainActor in
                        onFailure("Could not write the log to that location.")
                    }
                    return
                }
            }
        }
    }
}
#else
struct LogShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _: UIActivityViewController,
        context _: Context
    ) {}
}
#endif

struct LogSettingsView: View {
    let onChange: () -> Void

    static func followProfileTitle(profileLevel: String?) -> ClashDisplayText {
        guard let level = profileLevel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !level.isEmpty else { return .copy("Follow profile") }
        return .format("Follow profile (%@)", [level])
    }

     
     
     
     
     
     
    @State private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal
    private let defaults: UserDefaults
    @State private var recording: Bool
    @State private var retention: ClashLogRetention
    @State private var directive: String?

    init(defaults: UserDefaults = GlobalConfig.appGroupDefaults, onChange: @escaping () -> Void = {}) {
        self.defaults = defaults
        self.onChange = onChange
        _recording = State(initialValue: ClashLogSettings.isRecording(from: defaults))
        _retention = State(initialValue: ClashLogSettings.retention(from: defaults))
        _directive = State(initialValue: ClashLogSettings.levelDirective(from: defaults).rawValue)
    }

    var body: some View {
        ClashMacSettingsFormContainer {
            Section {
                Toggle("Record Logs", isOn: $recording)
                    .accessibilityIdentifier("logs.settings.recording")
                    .onChange(of: recording) { value in
                        ClashLogSettings.setRecording(
                            value,
                            in: defaults
                        )
                        onChange()
                    }
                Picker("Keep", selection: $retention) {
                    ForEach(ClashLogRetention.allCases, id: \.self) { option in
                        Text(clash: .copy(option.title)).tag(option)
                    }
                }
                .accessibilityIdentifier("logs.settings.keep")
                .onChange(of: retention) { value in
                    ClashLogSettings.setRetention(
                        value,
                        in: defaults
                    )
                    onChange()
                }
                 
                 
                 
                 
                 
                 
                Picker("Log level", selection: $directive) {
                    Text(clash: Self.followProfileTitle(
                        profileLevel: ClashLogSettings.activeProfileLogLevel(from: defaults)
                    )).tag(nil as String?)
                    ForEach(ClashLogLevel.allCases, id: \.self) { level in
                        Text(clash: .copy(level.rawValue.capitalized)).tag(level.rawValue as String?)
                    }
                }
                .accessibilityIdentifier("logs.settings.level")
                .onChange(of: directive) { value in
                    ClashLogSettings.setLevelDirective(
                        ClashLogSettings.LevelDirective(rawValue: value),
                        in: defaults
                    )
                    onChange()
                }
            } footer: {
                Text(clash: .copy("Record logs to help troubleshoot problems."))
            }
        }
        
        .clashPageTitle("Log Settings")
         
         
        .clashProductModalRoot(title: "Log Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !insideProductModal {
                    ClashSheetCloseButton { dismiss() }
                }
            }
        }
        .clashCapturesDismiss(dismiss)
    }
}

 
 
 
 
 
 
 
 
enum LogExportName {
     
     
     
     
    static func write(now: Date = Date(), logBatchesDropped: UInt64? = nil) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(current(now)).log")
        var facts = LogExportDeviceFacts.current(now: now)
        facts.logBatchesDropped = logBatchesDropped
        guard ClashLogStore.shared.writeExport(to: url, device: facts.render()) else {
            return nil
        }
        return url
    }

    static func current(_ now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
         
         
         
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "clash-logs-\(formatter.string(from: now))"
    }
}

enum LogRetentionCopy {
     
     
     
     
     
    static func summary(_ retention: ClashLogRetention) -> String {
        "Keeping \(retention.title), up to 20 MB a day — whichever runs out first."
    }
}

struct LogsContent: View {
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    let lines: [String]
    let isConnected: Bool
    let clear: () -> Void
    var command: ClashCommandClient? = nil
     
    var query = ""
     
    var isShown = true

    @State private var exportDocument =
        LogsTextDocument(text: "")
    @State private var exportError = ""
     
     
    @State private var recordingGeneration = 0
     
     
     
    private struct ShareTarget: Identifiable {
        let id = UUID()
        let url: URL
    }

    @State private var shareTarget: ShareTarget?
    @State private var confirmsExport = false
    @State private var showsSettings = false

    var body: some View {
         
         
         
        let _ = recordingGeneration
        let sharedSnapshot =
            ClashActivityIOSAdapter.snapshot(
                isConnected: isConnected,
                logLines: lines,
                exposesLogActions: true,
                isRecordingLogs: ClashLogSettings.isRecording(
                    from: GlobalConfig.appGroupDefaults
                ),
                logRetentionOptions: ClashLogRetention.allCases.map {
                    ClashLogRetentionOption(id: $0.rawValue, title: $0.title)
                },
                logRetention: ClashLogSettings.retention(
                    from: GlobalConfig.appGroupDefaults
                ).rawValue,
                logRetentionSummary: LogRetentionCopy.summary(
                    ClashLogSettings.retention(
                        from: GlobalConfig.appGroupDefaults
                    )
                ),
                 
                 
                logSeverityFilter: ClashLogSettings.severityFilter(
                    from: GlobalConfig.appGroupDefaults
                ),
                activeProfileLogLevel: ClashLogSettings.activeProfileLogLevel(
                    from: GlobalConfig.appGroupDefaults
                ),
                logLevelDirective: ClashLogSettings.levelDirective(
                    from: GlobalConfig.appGroupDefaults
                ).rawValue
            )
        ClashClientUI.ClashLogsView(
            snapshot: sharedSnapshot,
            actions: AppleClientActions(capability: .activity) {
                action in
                guard case .activity(let activity) = action else {
                    return
                }
                switch activity {
                case .clearLogs:
                    clear()
                case .exportLogs:
                     
                     
                     
                     
                     
                    exportError = ""
                    confirmsExport = true
                    return
                case .setLogRecording(let value):
                    ClashLogSettings.setRecording(
                        value,
                        in: GlobalConfig.appGroupDefaults
                    )
                    recordingGeneration &+= 1
                     
                    command?.refreshLogDisplayLevel()
                case .openLogSettings:
                    showsSettings = true
                case .setLogRetention(let raw):
                    guard let value = ClashLogRetention(rawValue: raw) else {
                        return
                    }
                    ClashLogSettings.setRetention(
                        value,
                        in: GlobalConfig.appGroupDefaults
                    )
                    recordingGeneration &+= 1
                case .setLogLevelDirective(let raw):
                    let directive = ClashLogSettings.LevelDirective(rawValue: raw)
                    ClashLogSettings.setLevelDirective(
                        directive,
                        in: GlobalConfig.appGroupDefaults
                    )
                    command?.refreshLogDisplayLevel()
                    recordingGeneration &+= 1
                case .setLogSeverityFilter(let levels):
                     
                     
                    ClashLogSettings.setSeverityFilter(
                        levels,
                        in: GlobalConfig.appGroupDefaults
                    )
                case .copyText(let value):
                    ClashClipboard.copy(value, feedback: feedback, operation: "logs.copy")
                case .refresh,
                     .closeConnection,
                     .closeAllConnections,
                     .clearRequests:
                    break
                }
            },
            presentationClass:
                horizontalSizeClass == .regular
                    ? .regularTouch
                    : .compactTouch,
            palette: ClashActivityIOSAdapter.palette,
            query: query,
            isShown: isShown
        ) { symbol in
            ClashSymbolImage(symbol: symbol)
        }
#if !os(macOS)
        .sheet(item: $shareTarget) { target in
            LogShareSheet(activityItems: [target.url])
                .clashModalPresentation(.page)
        }
#endif
        .clashProductModal(isPresented: $showsSettings, role: .form) {
            ClashFeatureNavigationContainer {
                LogSettingsView {
                    command?.refreshLogDisplayLevel()
                    recordingGeneration &+= 1
                }
            }
            .clashModalPresentation(.form)
        }
        .alert("Export This Log?", isPresented: $confirmsExport) {
            Button("Export", role: .destructive) { performExport() }
            Button("Cancel", role: .cancel) { confirmsExport = false }
        } message: {
            Text("The log is exported exactly as written, so it can contain your servers and any credential a line mentions. Share it only with someone you would show your configuration to.")
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { !exportError.isEmpty },
                set: { presented in
                    if !presented {
                        exportError = ""
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                exportError = ""
            }
        } message: {
            Text(exportError)
        }
    }

     
     
     
     
     
     
     
    private func performExport() {
        confirmsExport = false
        exportError = ""
         
         
        let dropped = command?.runtimeDiagnostics?.extensionLogBatchesDropped
#if os(macOS)
        MacSavePanel.write(
            suggestedName: "\(LogExportName.current()).log",
            writing: {
                var facts = LogExportDeviceFacts.current()
                facts.logBatchesDropped = dropped
                return ClashLogStore.shared.writeExport(to: $0, device: facts.render())
            },
            onFailure: { message in exportError = message }
        )
#else
        if let url = LogExportName.write(logBatchesDropped: dropped) {
             
            shareTarget = ShareTarget(url: url)
        } else if let feedback {
             
            feedback.show(.error(title: ClashFeedbackCopy.couldNotSave, message: .copy("Could not prepare the log for sharing."),
                                 accessibilityIdentifier: "feedback.logs.export"), operation: "logs.export")
        } else {
            exportError = "Could not prepare the log for sharing."
        }
#endif
    }
}

private struct LogsTextDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText]
    }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data =
                configuration.file.regularFileContents,
              let text = String(
                data: data,
                encoding: .utf8
              )
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(
        configuration _: WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents: Data(text.utf8)
        )
    }
}


