import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVRulesScreen: View {
    @Binding var state: ClashTVProductState
     
     
     
    var onNeedMoreRules: ((ClashStructuredRule.Category) -> Void)? = nil

    @State private var shownCategory: ClashStructuredRule.Category = .domain
    @State private var explainedRule: ClashRuleLineSnapshot?

     
     
     
     
    struct Shelves: Equatable {
        var total: Int
        var counts: [ClashStructuredRule.Category: Int]
        var neverMatching: [ClashStructuredRule.Category: Int]
        var lines: [ClashStructuredRule.Category: [ClashRuleLineSnapshot]]
    }

    static func shelves(of state: ClashTVProductState) -> Shelves {
        if let indexed = state.indexedRules {
            var counts: [ClashStructuredRule.Category: Int] = [:]
            var inert: [ClashStructuredRule.Category: Int] = [:]
            for category in ClashStructuredRule.Category.allCases {
                counts[category] = indexed.count(in: category)
                inert[category] = indexed.neverMatching(in: category)
            }
            return Shelves(total: indexed.total, counts: counts, neverMatching: inert, lines: indexed.loaded)
        }
        let groups = group(state.rules)
        return Shelves(total: state.rules.count,
                       counts: groups.mapValues(\.count),
                       neverMatching: groups.mapValues { $0.filter { neverMatches($0.type) }.count },
                       lines: groups)
    }

    var body: some View {
        if state.indexedRules == nil, let read = state.indexedRulesRead {
             
             
            Self.indexRead(read)
        } else {
            let shelves = Self.shelves(of: state)
            HStack(alignment: .top, spacing: 40) {
                categories(shelves)
                    .frame(maxWidth: 520)
                rules(shelves.lines[shownCategory] ?? [], count: shelves.counts[shownCategory] ?? 0)
            }
        }
    }

    @ViewBuilder
    private static func indexRead(_ read: ClashTVIndexedRulesRead) -> some View {
        switch read {
        case .reading:
            ProgressView("Loading Rules")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            ContentUnavailableView("Rules Can't Be Read Right Now",
                                   systemImage: ClashSymbol.exclamationmarkTriangle.rawValue)
        }
    }

     

    private func categories(_ shelves: Shelves) -> some View {
        List {
            Section(Self.listHeader(count: shelves.total)) {
                ForEach(ClashStructuredRule.Category.allCases) { category in
                    let count = shelves.counts[category] ?? 0
                    let inert = shelves.neverMatching[category] ?? 0
                    Button {
                        shownCategory = category
                    } label: {
                        LabeledContent {
                            Text(count.formatted())
                                .monospacedDigit()
                        } label: {
                            Text(category.title.localizedForTelevision)
                            if let subtitle = Self.groupSubtitle(neverMatching: inert) {
                                Text(subtitle)
                            }
                        }
                    }
                    .onClashTVFocus {
                        shownCategory = category
                        explainedRule = nil
                    }
                    .accessibilityIdentifier("tvos.rules.category.\(category.rawValue)")
                }
            }
        }
        .listStyle(.grouped)
        .safeAreaPadding(.horizontal, 44)
    }

     

    private func rules(_ lines: [ClashRuleLineSnapshot], count: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.header(category: shownCategory, count: count))
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            List {
                 
                ForEach(Array(lines.enumerated()), id: \.offset) { place, rule in
                    Button {} label: { row(rule) }
                        .onClashTVFocus { explainedRule = rule }
                        .onAppear {
                             
                            if Self.needsMore(at: place, read: lines.count, count: count) {
                                onNeedMoreRules?(shownCategory)
                            }
                        }
                }
            }
             
             
             
             
            .id(shownCategory)
             
             
             
            .listStyle(.grouped)
             
             
             
             
             
             
            .safeAreaPadding(.horizontal, 24)
            .safeAreaPadding(.vertical, 20)
             
             
             
            Text(explainedRule.map(Self.explanation(for:)) ?? " ")
                .font(.body)
                .foregroundStyle(
                    explainedRule.map { Self.neverMatches($0.type) } == true
                        ? AnyShapeStyle(.orange)
                        : AnyShapeStyle(.secondary)
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 80, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ rule: ClashRuleLineSnapshot) -> some View {
        let inert = Self.neverMatches(rule.type)
        return HStack(spacing: 20) {
             
             
            Text(rule.type)
                .font(.caption.monospaced())
                .foregroundStyle(inert ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(minWidth: 220, alignment: .leading)
            Text(rule.payload.isEmpty ? "—" : rule.payload)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 20)
            Text(Self.trailing(for: rule))
                .font(.body)
                .foregroundStyle(inert ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
    }

     

     
     
    static func needsMore(at place: Int, read: Int, count: Int) -> Bool {
        read < count && place >= read - 20
    }

     
     
     
    static func category(of type: String) -> ClashStructuredRule.Category {
        ClashStructuredRule.Action(rawValue: type)?.category ?? .advanced
    }

     
    static func group(_ lines: [ClashRuleLineSnapshot]) -> [ClashStructuredRule.Category: [ClashRuleLineSnapshot]] {
        var groups: [ClashStructuredRule.Category: [ClashRuleLineSnapshot]] = [:]
        for line in lines {
            groups[category(of: line.type), default: []].append(line)
        }
        return groups
    }

     
     
     
     
     
     
     
    static let neverMatchingKinds: Set<String> =
        ClashAppleRuntimeProfile.tvosPacketTunnel.keptNeverMatchRuleActionNames

    static func neverMatches(_ type: String) -> Bool {
        neverMatchingKinds.contains(type)
    }

     
     
    static func trailing(for rule: ClashRuleLineSnapshot) -> String {
        neverMatches(rule.type) ? String(localized: "Never matches") : rule.target
    }

     
    static func listHeader(count: Int) -> String {
        String(localized: "Rules · \(count.formatted())")
    }

     
     
    static func header(category: ClashStructuredRule.Category, count: Int) -> String {
        let title = category.title.localizedForTelevision
        return count == 1
            ? String(localized: "\(title) · 1 rule · in match order")
            : String(localized: "\(title) · \(count.formatted()) rules · in match order")
    }

    static func groupSubtitle(neverMatching count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: String(localized: "1 never matches here")
        default: String(localized: "\(count) never match here")
        }
    }

     
     
     
     
    static func explanation(for rule: ClashRuleLineSnapshot) -> String {
        if neverMatches(rule.type) {
            return String(localized: "This rule matches the app that made the connection. Apple TV doesn't say which app that is, so this rule never matches here and the next rule decides.")
        }
        return ClashStructuredRule.Action(rawValue: rule.type)?.summary.localizedForTelevision ?? rule.raw
    }
}
