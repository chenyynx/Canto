import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ConfigDeviationRow: View {

    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var fieldCopy
    let deviation: ConfigDeviation
     
     
    var identifierPrefix: String
     
     
     
     
     
    var speaksCopy = false

     
     
    static func title(of deviation: ConfigDeviation, speaksCopy: Bool, copy: ConfigurationFieldCopy,
                      locale: Locale) -> String {
        guard speaksCopy else { return deviation.title }
        return copy.entry(forPath: deviation.configKey, language: .init(locale: locale))?.title ?? deviation.title
    }

     
     
     
    static func line(of deviation: ConfigDeviation, speaksCopy: Bool, copy: ConfigurationFieldCopy,
                     locale: Locale) -> ClashDisplayText {
        if speaksCopy, let words = copy.platformWords(forPath: deviation.configKey, language: .init(locale: locale)) {
            return .verbatim(words)
        }
        return DeviationPlainLanguage.whatHappened(deviation, locale: locale)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
             
             
             
             
             
            if deviation.effect?.isLoud == true {
                Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                    .foregroundStyle(Color.orange)
                    .accessibilityIdentifier(identifierPrefix + ".loud")
            }
            body(for: deviation)
        }
         
         
         
         
        .accessibilityIdentifier(
            identifierPrefix + "." + deviation.title.replacingOccurrences(of: " ", with: "-")
        )
    }

    private func body(for deviation: ConfigDeviation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
             
             
             
            Text(clash: .verbatim(Self.title(of: deviation, speaksCopy: speaksCopy, copy: fieldCopy, locale: locale)))
                .font(.subheadline)
             
             
             
             
             
            Text(clash: Self.line(of: deviation, speaksCopy: speaksCopy, copy: fieldCopy, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !speaksCopy, let pair = DeviationPlainLanguage.valuePair(deviation, locale: locale) {
                Text(clash: pair)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(
                        identifierPrefix + ".given."
                            + deviation.title.replacingOccurrences(of: " ", with: "-")
                    )
            }
            if let action = DeviationPlainLanguage.whatToDo(deviation, locale: locale) {
                 
                 
                Text(clash: action)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
             
             
             
             
             
             
             
             
             
             
             
        }
    }

}

 
 
 
 
 
 
 
 
 
 
 
 
struct ConfigDeviationSection: View {
    let report: ConfigDeviationReport?
     
     
    let fields: [String]
    var identifierPrefix: String
     
    var speaksCopy = false

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static let visibleBeforeShowAll = 4
    @State private var revealed = false

    private var shown: [ConfigDeviation] {
        revealed ? matches : Array(matches.prefix(Self.visibleBeforeShowAll))
    }

    private var matches: [ConfigDeviation] {
        guard let report else { return [] }
        return Self.rows(in: report, fields: fields)
    }

     
     
     
     
     
     
     
    static func rows(
        in report: ConfigDeviationReport,
        fields: [String]
    ) -> [ConfigDeviation] {
        report.deviations.filter { claims(fields, $0.configKey) }
    }

     
     
     
     
     
     
     
    static func claims(_ keys: [String], _ key: String) -> Bool {
        keys.contains { claim in
            claim.hasSuffix(".") ? key.hasPrefix(claim) : key == claim
        }
    }

    var body: some View {
         
         
         
         
         
        if !matches.isEmpty {
            Section {
                ForEach(shown) { deviation in
                    ConfigDeviationRow(deviation: deviation, identifierPrefix: identifierPrefix, speaksCopy: speaksCopy)
                }
                if shown.count < matches.count {
                    Button {
                        revealed = true
                    } label: {
                        Text(clash: .format(
                            "Show all %@ fields",
                            ["\(matches.count)"]
                        ))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier(identifierPrefix + ".show-all")
                }
            } header: {
                 
                 
                 
                Text(clash: .format(
                    "What the Running Core Did (%@)",
                    ["\(matches.count)"]
                ))
                    .accessibilityIdentifier(identifierPrefix + ".heading")
            } footer: {
                Text("Reported by the core that is running, about the fields on this page. Editing them changes the next start, not this one.")
            }
        }
    }
}
