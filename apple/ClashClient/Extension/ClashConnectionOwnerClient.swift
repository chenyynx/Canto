#if os(macOS)
import Darwin
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
final class ClashConnectionOwnerClient: @unchecked Sendable {
    struct Owner: Equatable, Sendable {
        let userID: Int32
        let userName: String
        let processPath: String
    }

    private let path: String
    private let deadline: Int32  
    private let retryAfter: UInt64 = 1_000_000_000
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var failedAt: UInt64 = 0
    private var buffer = [UInt8]()

     
     
     
    init?(container: URL, deadlineMilliseconds: Int32 = 150) {
        let path = container.appendingPathComponent("owner.sock").path
        guard path.utf8.count < 104 else { return nil }
        self.path = path
        self.deadline = deadlineMilliseconds
    }

    func owner(
        ipProtocol: Int32, sourceAddress: String, sourcePort: Int32,
        destinationAddress: String, destinationPort: Int32
    ) -> Owner? {
        guard ipProtocol == 6 || ipProtocol == 17 else { return nil }
        let question = "Q \(ipProtocol) \(sourceAddress) \(sourcePort) \(destinationAddress) \(destinationPort)\n"
        lock.lock()
        defer { lock.unlock() }
        guard connectIfNeeded() else { return nil }
        guard send(question), let line = receiveLine() else {
            disconnect(failed: true)
            return nil
        }
        return Self.parse(line)
    }

    static func parse(_ line: String) -> Owner? {
        guard line.hasPrefix("O ") else { return nil }
        let fields = line.dropFirst(2).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3, let uid = Int32(fields[0]), !fields[2].isEmpty else { return nil }
        return Owner(userID: uid, userName: fields[1], processPath: fields[2])
    }

    private func connectIfNeeded() -> Bool {
        if fd >= 0 { return true }
        let now = DispatchTime.now().uptimeNanoseconds
        if failedAt != 0, now &- failedAt < retryAfter { return false }
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { failedAt = now; return false }
        var on: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(socketFD)
            failedAt = now
            return false
        }
        fd = socketFD
        failedAt = 0
        buffer.removeAll()
        return true
    }

    private func disconnect(failed: Bool) {
        if fd >= 0 { close(fd) }
        fd = -1
        buffer.removeAll()
        if failed { failedAt = DispatchTime.now().uptimeNanoseconds }
    }

    private func send(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var sent = 0
        while sent < bytes.count {
            guard wait(POLLOUT) else { return false }
            let count = bytes.withUnsafeBytes { write(fd, $0.baseAddress! + sent, bytes.count - sent) }
            guard count > 0 else { return false }
            sent += count
        }
        return true
    }

    private func receiveLine() -> String? {
        var chunk = [UInt8](repeating: 0, count: 2048)
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<newline], as: UTF8.self)
                buffer.removeSubrange(...newline)
                return line
            }
            guard wait(POLLIN) else { return nil }
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<count])
            if buffer.count > 8192 { return nil }
        }
    }

    private func wait(_ events: Int32) -> Bool {
        var descriptor = pollfd(fd: fd, events: Int16(events), revents: 0)
        return poll(&descriptor, 1, deadline) == 1 && descriptor.revents & Int16(events) != 0
    }
}
#endif
