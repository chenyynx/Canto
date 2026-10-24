import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashActivityProjectionMemo {
    public init() {}

    private struct LogsKey: Equatable {
        let lines: [String]
        let query: String
        let severities: Set<ClashActivityLogSeverity>
    }

    private var logsKey: LogsKey?
    private var logsValue: [ClashActivityLogEntry] = []
     
     
     
     
    private var logEntries: [ClashActivityLogEntry.ID: ClashActivityLogEntry] = [:]
    private let logEntryLimit = 8192

     
     
    public private(set) var builds = 0

    private struct RequestsKey: Equatable {
        let values: [ClashActivityRequestSnapshot]
        let query: String
        let keywords: Set<String>
    }

    private var requestsKey: RequestsKey?
    private var requestsValue: [ClashActivityRequestSnapshot] = []

     
     
     
     
     
    public func requests(
        _ values: [ClashActivityRequestSnapshot],
        query: String,
        keywords: Set<String>
    ) -> [ClashActivityRequestSnapshot] {
        let key = RequestsKey(values: values, query: query, keywords: keywords)
        if let requestsKey, requestsKey == key { return requestsValue }
        builds += 1
        let value = ClashActivityProjection.requests(
            values, query: query, keywords: keywords
        )
        requestsKey = key
        requestsValue = value
        return value
    }

    public func logs(
        _ lines: [String],
        query: String,
        severities: Set<ClashActivityLogSeverity>
    ) -> [ClashActivityLogEntry] {
        let key = LogsKey(lines: lines, query: query, severities: severities)
        if let logsKey, logsKey == key { return logsValue }
        builds += 1
        if logEntries.count >= logEntryLimit {
            logEntries.removeAll(keepingCapacity: true)
        }
        let value = ClashActivityProjection.logs(
            lines, query: query, severities: severities, entries: &logEntries
        )
        logsKey = key
        logsValue = value
        return value
    }
}
