#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
enum ModuleDecryptionChoice: String, Codable, Equatable, Sendable {
    case followsTrust
    case offByReader

    private struct Record: Codable {
        let choice: ModuleDecryptionChoice
        let at: Date
    }

    static func file(_ locations: ModuleEngineLocations) -> URL {
        locations.stateDirectory.appendingPathComponent("decryption-choice.json")
    }

     
    static func read(_ locations: ModuleEngineLocations) -> ModuleDecryptionChoice? {
        ModuleEngineFiles.read(Record.self, from: file(locations), maximumBytes: 1_024)?.choice
    }

    static func record(_ choice: ModuleDecryptionChoice, in locations: ModuleEngineLocations, at now: Date = Date()) {
        guard read(locations) != choice,
              let data = try? ModuleJSON.encoder().encode(Record(choice: choice, at: now)) else { return }
        try? ModuleEngineFiles.write(data, to: file(locations))
    }
}
#endif
