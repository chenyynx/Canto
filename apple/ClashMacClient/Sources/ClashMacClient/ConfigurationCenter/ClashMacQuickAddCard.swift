import ClashClientUI
import SwiftUI

 
 
 
 
 
public enum ClashMacQuickAddStatus: Equatable, Sendable {
     
    case busy(String)
     
    case failure(String)
     
     
    case notice(ClashDisplayText)
}

 
 
public struct ClashMacQuickAddOffer {
    public let title: String
    public let action: () -> Void
    public init(title: String, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }
}

 
 
 
 
 
public struct ClashMacQuickAddDoors: Equatable, Sendable {
    public let scans: Bool
    public let importsFile: Bool

    public init(scans: Bool = true, importsFile: Bool = true) {
        self.scans = scans
        self.importsFile = importsFile
    }

    var isEmpty: Bool { !scans && !importsFile }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashMacQuickAddCard<Paste: View>: View {
    private let header: ClashDisplayText
    @Binding private var text: String
    private let placeholder: String
    private let status: ClashMacQuickAddStatus?
     
    private let offer: ClashMacQuickAddOffer?
    private let isBusy: Bool
    private let doors: ClashMacQuickAddDoors
    private let identifiers: ClashMacQuickAddIdentifiers
    private let submit: () -> Void
    private let scan: () -> Void
    private let importFile: () -> Void
    private let paste: () -> Paste

    public init(
        header: ClashDisplayText,
        text: Binding<String>,
        placeholder: String,
        status: ClashMacQuickAddStatus?,
        offer: ClashMacQuickAddOffer? = nil,
        isBusy: Bool,
        doors: ClashMacQuickAddDoors = .init(),
        identifiers: ClashMacQuickAddIdentifiers,
        submit: @escaping () -> Void,
        scan: @escaping () -> Void,
        importFile: @escaping () -> Void,
        @ViewBuilder paste: @escaping () -> Paste
    ) {
        self.header = header
        _text = text
        self.placeholder = placeholder
        self.status = status
        self.offer = offer
        self.isBusy = isBusy
        self.doors = doors
        self.identifiers = identifiers
        self.submit = submit
        self.scan = scan
        self.importFile = importFile
        self.paste = paste
    }

    @Environment(\.clashMacGroupedList) private var grouped

     
     
     
    @ViewBuilder
    public var body: some View {
        if grouped {
            Text(clash: header)
                .clashMacGroupHeader(margin: 0)
            let rows = boxRows
            ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                boxRow(row)
                    .clashMacGroupRow(first: index == 0, last: index == rows.count - 1, margin: 0)
            }
        } else {
            section
        }
    }

    private enum BoxRow: Hashable { case field, status, offer }

    private var boxRows: [BoxRow] {
        guard let status else { return [.field] }
        if offer != nil, case .failure = status { return [.field, .status, .offer] }
        return [.field, .status]
    }

    @ViewBuilder
    private func boxRow(_ row: BoxRow) -> some View {
        switch row {
        case .field:
            fieldRow
        case .status:
            if let status { statusRow(status) }
        case .offer:
            if let offer {
                Button(action: offer.action) { Text(verbatim: offer.title) }
                    .disabled(isBusy)
                    .accessibilityIdentifier(identifiers.nodesOnlyIdentifier)
            }
        }
    }

    private var section: some View {
        Section {
            fieldRow
             
             
            if let status {
                statusRow(status)
                if let offer, case .failure = status {
                    Button(action: offer.action) { Text(verbatim: offer.title) }
                        .disabled(isBusy)
                        .accessibilityIdentifier(identifiers.nodesOnlyIdentifier)
                }
            }
        } header: {
            Text(clash: header)
        }
    }

    private var fieldRow: some View {
             
             
             
             
             
             
             
            HStack(spacing: ClashTheme.Spacing.compact) {
                 
                 
                TextField("", text: $text, prompt: Text(verbatim: placeholder))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                    .disabled(isBusy)
                    .accessibilityIdentifier(identifiers.linkIdentifier)
                 
                 
                 
                 
                 
                 
                 
                Group {
                    paste()
                    if doors.scans {
                        Button(action: scan) {
                            Label {
                                Text(ClashCopy.key("Scan"))
                            } icon: {
                                ClashSymbolImage(symbol: .qrcodeViewfinder)
                            }
                        }
                        .accessibilityIdentifier(identifiers.scanIdentifier)
                    }
                    if doors.importsFile {
                         
                         
                         
                         
                        Button(action: importFile) {
                            Label {
                                Text(ClashCopy.key("Import"))
                            } icon: {
                                ClashSymbolImage(symbol: .arrowUpDocument)
                            }
                        }
                        .accessibilityIdentifier(identifiers.fileIdentifier)
                    }
                }
                .clashMacFormActionChrome()
            }
            .disabled(isBusy)
             
             
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    @ViewBuilder
    private func statusRow(_ status: ClashMacQuickAddStatus) -> some View {
        switch status {
        case .busy(let host):
            HStack(spacing: ClashTheme.Spacing.compact) {
                ProgressView().controlSize(.small)
                Text(clash: .format("Downloading %@…", [host]))
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier(identifiers.statusIdentifier)
        case .failure(let message):
             
             
            Text(verbatim: message)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifiers.statusIdentifier)
        case .notice(let text):
            Text(clash: text)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifiers.statusIdentifier)
        }
    }
}

 
 
 
public struct ClashMacQuickAddIdentifiers: Sendable {
    public let linkIdentifier: String
    public let scanIdentifier: String
    public let fileIdentifier: String
    public let statusIdentifier: String
     
    public let nodesOnlyIdentifier: String

    public init(
        linkIdentifier: String,
        scanIdentifier: String,
        fileIdentifier: String,
        statusIdentifier: String,
        nodesOnlyIdentifier: String = ""
    ) {
        self.linkIdentifier = linkIdentifier
        self.scanIdentifier = scanIdentifier
        self.fileIdentifier = fileIdentifier
        self.statusIdentifier = statusIdentifier
        self.nodesOnlyIdentifier = nodesOnlyIdentifier
    }
}

