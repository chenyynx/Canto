import Foundation

 
 
 
 
 
 
 
 
 
 
 
public struct ConfigurationLibraryRemoval: Equatable, Sendable {
    public struct PlacedSource: Equatable, Sendable {
        public let index: Int
        public let record: ConfigurationSourceRecord
    }

    public struct PlacedRuleScheme: Equatable, Sendable {
        public let index: Int
        public let scheme: ConfigurationRuleScheme
    }

     
    public let sources: [PlacedSource]
    public let rules: [PlacedRuleScheme]
    public let updateIssues: [ConfigurationUpdateIssue]
     
    public let payloads: [ConfigurationSourcePayload]
     
     
     
    public let leftSources: [String: Trace]
    public let leftRules: [String: Trace]

     
     
     
    public struct Trace: Equatable, Sendable {
        let source: ConfigurationSourceRecord?
        let scheme: ConfigurationRuleScheme?
        var retained: Bool { (source?.isRetainedSnapshot ?? scheme?.isRetainedSnapshot) == true }

        init(_ record: ConfigurationSourceRecord) { source = record; scheme = nil }
        init(_ scheme: ConfigurationRuleScheme) { source = nil; self.scheme = scheme }
    }

    public var isEmpty: Bool { sources.isEmpty && rules.isEmpty && updateIssues.isEmpty }

     
     
    func untouched(in library: ConfigurationLibrarySnapshot) -> Bool {
        let sourcesOK = sources.allSatisfy { placed in
            let now = library.sources.first { $0.id == placed.record.id }
            guard let left = leftSources[placed.record.id] else { return now == nil }
            guard let now else { return left.retained }
            return Trace(now) == left
        }
        let rulesOK = rules.allSatisfy { placed in
            let now = library.rules.first { $0.id == placed.scheme.id }
            guard let left = leftRules[placed.scheme.id] else { return now == nil }
            guard let now else { return left.retained }
            return Trace(now) == left
        }
        return sourcesOK && rulesOK
    }
}

extension ConfigurationLibraryStore {
     
     
    public func removal(from before: ConfigurationLibrarySnapshot,
                        to prepared: ConfigurationLibrarySnapshot) throws -> ConfigurationLibraryRemoval {
         
         
         
         
        let candidate = Self.pruningUnreferencedRetainedRecords(prepared).snapshot
        let sources = before.sources.enumerated().compactMap { index, record in
            candidate.sources.contains(record) ? nil : ConfigurationLibraryRemoval.PlacedSource(index: index, record: record)
        }
        let rules = before.rules.enumerated().compactMap { index, scheme in
            candidate.rules.contains(scheme) ? nil : ConfigurationLibraryRemoval.PlacedRuleScheme(index: index, scheme: scheme)
        }
        let issues = (before.updateIssues ?? []).filter { !(candidate.updateIssues ?? []).contains($0) }
        let payloads = try sources.map { try payload(ConfigurationSourceVersion($0.record)) }
        var leftSources: [String: ConfigurationLibraryRemoval.Trace] = [:]
        for placed in sources {
            if let kept = candidate.sources.first(where: { $0.id == placed.record.id }) { leftSources[placed.record.id] = .init(kept) }
        }
        var leftRules: [String: ConfigurationLibraryRemoval.Trace] = [:]
        for placed in rules {
            if let kept = candidate.rules.first(where: { $0.id == placed.scheme.id }) { leftRules[placed.scheme.id] = .init(kept) }
        }
        return ConfigurationLibraryRemoval(sources: sources, rules: rules, updateIssues: issues, payloads: payloads,
                                           leftSources: leftSources, leftRules: leftRules)
    }

     
     
     
     
     
     
    public func restore(_ removal: ConfigurationLibraryRemoval,
                        expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
         
         
         
        _ = expectedGeneration
        guard removal.untouched(in: candidate) else {
            throw ConfigurationLibraryError.staleGeneration
        }
        let generation = candidate.generation
        for placed in removal.sources.sorted(by: { $0.index < $1.index }) {
            if let index = candidate.sources.firstIndex(where: { $0.id == placed.record.id }) {
                candidate.sources[index] = placed.record
            } else {
                candidate.sources.insert(placed.record, at: min(placed.index, candidate.sources.count))
            }
        }
        for placed in removal.rules.sorted(by: { $0.index < $1.index }) {
            if let index = candidate.rules.firstIndex(where: { $0.id == placed.scheme.id }) {
                candidate.rules[index] = placed.scheme
            } else {
                candidate.rules.insert(placed.scheme, at: min(placed.index, candidate.rules.count))
            }
        }
        if !removal.updateIssues.isEmpty {
            var issues = candidate.updateIssues ?? []
            for issue in removal.updateIssues where !issues.contains(issue) { issues.append(issue) }
            candidate.updateIssues = issues
        }
        return try commit(candidate, payloads: removal.payloads, expectedGeneration: generation)
    }
}
