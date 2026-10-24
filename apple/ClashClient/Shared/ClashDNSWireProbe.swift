import Foundation
import Network

 
 
 
 
 
 
 
enum ClashDNSWireProbe {
    static func query(name: String, type: String, server: String, port: UInt16 = 53, timeout: TimeInterval = 8) async -> Data {
        guard let packet = packet(name: name, type: type) else {
            return Data(#"{"error":"bad question"}"#.utf8)
        }
        let host = NWEndpoint.Host(server)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return Data(#"{"error":"bad port"}"#.utf8) }
        let connection = NWConnection(host: host, port: nwPort, using: .udp)
        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var finished = false
            func finish(_ data: Data) {
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: data)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error { finish(Data("{\"error\":\"send: \(error)\"}".utf8)) }
                    })
                    connection.receiveMessage { data, _, _, error in
                        if let error { finish(Data("{\"error\":\"receive: \(error)\"}".utf8)); return }
                        finish(reply(data ?? Data(), questionID: packet.prefix(2)))
                    }
                case .failed(let error):
                    finish(Data("{\"error\":\"connection: \(error)\"}".utf8))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(Data(#"{"error":"wire: timeout"}"#.utf8))
            }
        }
    }

     

    static let types: [String: UInt16] = ["A": 1, "AAAA": 28, "PTR": 12, "TXT": 16]

     
    static func packet(name: String, type: String) -> Data? {
        guard let qtype = types[type.uppercased()] else { return nil }
        var data = Data()
        let id = UInt16.random(in: 1...UInt16.max)
        data.append(contentsOf: [UInt8(id >> 8), UInt8(id & 0xff), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0])
        for label in name.split(separator: ".", omittingEmptySubsequences: true) {
            let bytes = Array(label.utf8)
            guard bytes.count < 64 else { return nil }
            data.append(UInt8(bytes.count)); data.append(contentsOf: bytes)
        }
        data.append(0)
        data.append(contentsOf: [UInt8(qtype >> 8), UInt8(qtype & 0xff), 0, 1])
        return data
    }

     
     
     
    static func reply(_ data: Data, questionID: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { return Data(#"{"error":"short reply"}"#.utf8) }
        guard Data(bytes[0..<2]) == questionID else { return Data(#"{"error":"id mismatch"}"#.utf8) }
        let rcode = Int(bytes[3] & 0x0f)
        let qdcount = Int(bytes[4]) << 8 | Int(bytes[5])
        let ancount = Int(bytes[6]) << 8 | Int(bytes[7])
        var offset = 12
        func skipName() -> Bool {
            while offset < bytes.count {
                let length = Int(bytes[offset])
                if length == 0 { offset += 1; return true }
                if length & 0xC0 == 0xC0 { offset += 2; return true }
                offset += 1 + length
            }
            return false
        }
        for _ in 0..<qdcount { guard skipName(), offset + 4 <= bytes.count else { return Data(#"{"error":"bad question section"}"#.utf8) }; offset += 4 }
        var answers: [[String: Any]] = []
        for _ in 0..<ancount {
            guard skipName(), offset + 10 <= bytes.count else { break }
            let rtype = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            let rdlength = Int(bytes[offset + 8]) << 8 | Int(bytes[offset + 9])
            offset += 10
            guard offset + rdlength <= bytes.count else { break }
            let rdata = bytes[offset..<offset + rdlength]
            offset += rdlength
            var text = "type \(rtype)"
            if rtype == 1, rdlength == 4 { text = rdata.map(String.init).joined(separator: ".") }
            if rtype == 28, rdlength == 16 {
                text = stride(from: 0, to: 16, by: 2).map { String(format: "%x", Int(rdata[rdata.startIndex + $0]) << 8 | Int(rdata[rdata.startIndex + $0 + 1])) }.joined(separator: ":")
            }
            answers.append(["type": rtype, "data": text])
        }
        let object: [String: Any] = ["Status": rcode, "Answer": answers]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data(#"{"error":"encode"}"#.utf8)
    }
}
