import Clash
import ClashClientUI
import SwiftUI

typealias ClashRule = ClashRuntimeRule

extension ClashRuntimeRule {
    var proxy: String { target }
}

enum ClashRulesPayload {
    static func decode(_ data: Data?) -> [ClashRule] {
        ClashRuntimeRulesPayload.decode(data)
    }
}

typealias DNSQueryAnswer = ClashDNSQueryAnswer

extension ClashDNSQueryAnswer {
    var TTL: Int? { ttl }
}

struct DNSQueryResponse: Decodable {
    let Answer: [DNSQueryAnswer]?
}

extension ClashRuleEntryCounter {
     
     
     
     
     
     
    static func app(
        ruleSets: RuleSetCounts,
        read: @escaping @Sendable () async -> [String: Int]?
    ) -> ClashRuleEntryCounter {
         
         
        ClashRuleEntryCounter { key in
            if key.kind == .ruleSet {
                return await ruleSets.value(read: read)[key.value]
            }
            return await databaseCount(key)
        }
    }

    private static func databaseCount(_ key: Key) async -> Int? {
         
         
         
         
        await withCheckedContinuation { continuation in
            countingQueue.async {
                guard AppCoreSetup.ensureForReaders() else {
                    continuation.resume(returning: nil)
                    return
                }
                let count: Int
                switch key.kind {
                case .geoIP: count = ClashGeoIPNetworkCount(key.value)
                case .asn: count = ClashASNNetworkCount(key.value)
                case .ruleSet: count = -1
                }
                continuation.resume(returning: count >= 0 ? count : nil)
            }
        }
    }

    private static let countingQueue = DispatchQueue(label: "clash.rule-entry-count", qos: .utility)
}

 
 
 
 
 
 
 
 
 
 
 
 
actor RuleSetCounts {
    private var counts: [String: Int]?
    private var lastGood: [String: Int] = [:]
    private var generation = 0

    func value(read: @Sendable () async -> [String: Int]?) async -> [String: Int] {
        if let counts { return counts }
        let asked = generation
        guard let fresh = await read() else { return lastGood }
        guard asked == generation else { return fresh }
        counts = fresh
        lastGood = fresh
        return fresh
    }

    func forget() {
        counts = nil
        generation &+= 1
    }
}

 
struct ActiveRulesView: View {
    @ObservedObject var command: ClashCommandClient
    @State private var ruleSets = RuleSetCounts()
    @State private var ruleSetGeneration = 0

    var body: some View {
        ClashActiveRulesView(
            rules: command.rules,
            totalCount: command.rulesTotal,
            hits: command.ruleHits,
            isConnected: command.isConnected,
            entryCounter: .app(ruleSets: ruleSets, read: { [command] in
                 
                 
                 
                guard let catalog = try? await command.providerRuntimeCatalog() else { return nil }
                return catalog.ruleProviders.mapValues(\.ruleCount)
            }),
            ruleSetGeneration: ruleSetGeneration,
            refresh: { [ruleSets] in
                await ruleSets.forget()
                await command.fetchRules()
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .clashProviderContentChanged)) { _ in
            Task { @MainActor in
                await ruleSets.forget()
                ruleSetGeneration &+= 1
            }
        }
    }
}

 
struct DNSQueryView: View {
    @ObservedObject var command: ClashCommandClient

    var body: some View {
        ClashDNSQueryView(
            isConnected: command.isConnected,
            capabilities: ClashDNSQueryCapabilities(
                query: { name, type in
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    if let family = Self.addressFamily(for: type) {
                        let result = await Self.systemAnswer(
                            name: name,
                            type: type,
                            family: family
                        )
                        return ClashDNSResolution(
                            result: result,
                            answerSource: .systemResolver,
                            explain: await Self.explain(
                                command,
                                name: name,
                                type: type,
                                probe: false
                            )
                        )
                    }
                     
                     
                     
                    let explained = await Self.explain(
                        command,
                        name: name,
                        type: type,
                        probe: true
                    )
                     
                     
                     
                     
                    if let probed = explained?.probedResult {
                        return ClashDNSResolution(
                            result: probed,
                            answerSource: .core,
                            explain: explained
                        )
                    }
                     
                     
                    let rawResponse = await command.runDNSQuery(
                        name: name,
                        type: type
                    )
                    return ClashDNSResolution(
                        result: ClashDNSQueryResult(
                            rawResponse: rawResponse,
                            errorMessage:
                                rawResponse == nil
                                && !command.lastError.isEmpty
                                    ? command.lastError
                                    : nil
                        ),
                        answerSource: .core,
                        explain: explained
                    )
                },
                explain: { name, type in
                     
                     
                     
                    await Self.explain(
                        command,
                        name: name,
                        type: type,
                        probe: false
                    )
                },
                maintain: { action in
                    switch action {
                    case .dns:
                        await command.flushDNSCache()
                    case .fakeIP:
                        await command.flushFakeIPCache()
                    }
                    return command.lastError.isEmpty
                        ? nil
                        : command.lastError
                }
            )
        )
    }
}

extension DNSQueryView {
     
     
    static func explain(
        _ command: ClashCommandClient,
        name: String,
        type: String,
        probe: Bool
    ) async -> ClashDNSExplain? {
        guard let json = await command.explainDNS(
            name: name,
            type: type,
            probe: probe
        ) else { return nil }
        guard let explained = ClashDNSExplain.decode(json) else {
             
             
            ClashLogStore.shared.append(
                "dns explain not understood: "
                    + json.prefix(160),
                stream: .app,
                level: .warning
            )
            return nil
        }
        return explained
    }

     
    static func addressFamily(for type: String) -> Int32? {
        switch type {
        case "A": return AF_INET
        case "AAAA": return AF_INET6
        default: return nil
        }
    }

     
    static func recordCode(for type: String) -> Int {
        type == "AAAA" ? 28 : 1
    }

    static func systemAnswer(
        name: String,
        type: String,
        family: Int32
    ) async -> ClashDNSQueryResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ClashDNSQueryResult(answers: [], errorMessage: nil)
        }
        let addresses = await Task.detached(priority: .userInitiated) {
            LocalMappingEffect.systemAddresses(for: trimmed, family: family)
        }.value
        guard !addresses.isEmpty else {
            return ClashDNSQueryResult(
                answers: [],
                errorMessage: "No address was returned for this name."
            )
        }
        return ClashDNSQueryResult(
            answers: addresses.map { address in
                ClashDNSQueryAnswer(
                    name: trimmed,
                    type: recordCode(for: type),
                     
                     
                    ttl: nil,
                    data: address
                )
            }
        )
    }
}
