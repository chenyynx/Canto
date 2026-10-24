#if os(iOS) || os(macOS)
import Compression
import Darwin
import Foundation
import zlib

 
 
 
 
 
 
 
 

enum ModuleContentCoding: Equatable, Sendable {
    case identity
    case gzip
    case deflate
    case brotli
    case unsupported(String)

     
    static func parse(_ header: String?) -> [ModuleContentCoding] {
        guard let header else { return [] }
        return header.split(separator: ",").compactMap { raw in
            switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
            case "", "identity": return nil
            case "gzip", "x-gzip": return .gzip
            case "deflate": return .deflate
            case "br": return .brotli
            case let other: return .unsupported(other)
            }
        }
    }
}

struct ModuleDecodeResult: Equatable, Sendable {
    let data: Data
     
    let outputLimitExceeded: Bool
}

enum ModuleBodyDecoderError: Error, Equatable, Sendable {
    case corrupt(String)
    case unsupported(String)
     
    case windowTooLarge(Int)

     
    var reason: String {
        switch self {
        case .corrupt(let why): return "corrupt: \(why)"
        case .unsupported(let coding): return "\(coding) is not decoded"
        case .windowTooLarge(let window): return "its brotli window is \(window) bytes"
        }
    }
}

enum ModuleBodyDecoder {
    static let chunkSize = 32 * 1024

     
     
     
    static func decode(_ body: Data, coding: ModuleContentCoding, maximumOutputLength: Int) throws -> ModuleDecodeResult {
        let maximumOutputLength = max(0, maximumOutputLength)
        switch coding {
        case .identity:
            #if os(iOS)
             
             
            guard body.count > maximumOutputLength else { return ModuleDecodeResult(data: body, outputLimitExceeded: false) }
            #endif
             
             
             
             
            return ModuleDecodeResult(data: Data(body.prefix(maximumOutputLength)), outputLimitExceeded: body.count > maximumOutputLength)
        case .gzip:
            return try inflateBody(body, windowBits: 15 + 16, maximumOutputLength: maximumOutputLength)
        case .deflate:
            do {
                return try inflateBody(body, windowBits: 15, maximumOutputLength: maximumOutputLength)
            } catch ModuleBodyDecoderError.corrupt {
                 
                return try inflateBody(body, windowBits: -15, maximumOutputLength: maximumOutputLength)
            }
        case .brotli:
            return try brotliBody(body, maximumOutputLength: maximumOutputLength)
        case .unsupported(let name):
            throw ModuleBodyDecoderError.unsupported(name)
        }
    }

     
     
    static func brotliWindowBytes(_ body: Data) -> Int? {
        guard let first = body.first else { return nil }
        let windowBits: Int
        if first & 0x01 == 0 {
            windowBits = 16
        } else if Int(first >> 1) & 0x07 != 0 {
            windowBits = 17 + Int(first >> 1) & 0x07
        } else {
            let extended = Int(first >> 4) & 0x07
            if extended == 1 { return nil }
            windowBits = extended == 0 ? 17 : 8 + extended
        }
        return (1 << windowBits) - 16
    }

    private static func inflateBody(_ body: Data, windowBits: Int32, maximumOutputLength: Int) throws -> ModuleDecodeResult {
         
        let stream = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        stream.initialize(to: z_stream())
        defer {
            stream.deinitialize(count: 1)
            stream.deallocate()
        }
        guard inflateInit2_(stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ModuleBodyDecoderError.corrupt("zlib could not start")
        }
        defer { inflateEnd(stream) }
        let chunk = UnsafeMutablePointer<Bytef>.allocate(capacity: chunkSize)
        defer { chunk.deallocate() }
        var output = Data()
        var exceeded = false
        var status: Int32 = Z_OK
         
        body.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            stream.pointee.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.pointee.avail_in = uInt(source.count)
            reading: while true {
                stream.pointee.next_out = chunk
                stream.pointee.avail_out = uInt(chunkSize)
                status = zlib.inflate(stream, Z_NO_FLUSH)
                let produced = chunkSize - Int(stream.pointee.avail_out)
                if output.count + produced > maximumOutputLength {
                    exceeded = true
                    break reading
                }
                output.append(chunk, count: produced)
                switch status {
                case Z_OK:
                     
                    continue
                case Z_STREAM_END where windowBits > 15 && stream.pointee.avail_in > 0:
                     
                    guard inflateReset(stream) == Z_OK else {
                        status = Z_STREAM_ERROR
                        break reading
                    }
                default:
                    break reading
                }
            }
        }
        if exceeded { return ModuleDecodeResult(data: output, outputLimitExceeded: true) }
        guard status == Z_STREAM_END else { throw ModuleBodyDecoderError.corrupt("zlib status \(status)") }
        return ModuleDecodeResult(data: output, outputLimitExceeded: false)
    }

    private static func brotliBody(_ body: Data, maximumOutputLength: Int) throws -> ModuleDecodeResult {
        guard let window = brotliWindowBytes(body) else { throw ModuleBodyDecoderError.corrupt("not a brotli stream") }
        guard window <= maximumOutputLength else { throw ModuleBodyDecoderError.windowTooLarge(window) }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_BROTLI) == COMPRESSION_STATUS_OK else {
            throw ModuleBodyDecoderError.unsupported("br")
        }
        defer { compression_stream_destroy(stream) }
        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { chunk.deallocate() }
        var output = Data()
        var exceeded = false
        var status = COMPRESSION_STATUS_OK
        body.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count
             
             
            repeat {
                stream.pointee.dst_ptr = chunk
                stream.pointee.dst_size = chunkSize
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunkSize - stream.pointee.dst_size
                if output.count + produced > maximumOutputLength {
                    exceeded = true
                    break
                }
                output.append(chunk, count: produced)
            } while status == COMPRESSION_STATUS_OK
        }
        if exceeded { return ModuleDecodeResult(data: output, outputLimitExceeded: true) }
        guard status == COMPRESSION_STATUS_END else { throw ModuleBodyDecoderError.corrupt("brotli") }
        return ModuleDecodeResult(data: output, outputLimitExceeded: false)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleBodyLimits: Equatable, Sendable {
     
     
     
     
     
     
     
    var defaultBytes: Int
     
    var spillAbove: Int?
     
     
     
     
    var memoryGuard: ModuleBodyMemoryGuard? = nil

    static let iOS = ModuleBodyLimits(defaultBytes: 1 << 20, spillAbove: nil, memoryGuard: .iOS)
     
    static let macOS = ModuleBodyLimits(defaultBytes: 10 << 20, spillAbove: 1 << 20)

    static var current: ModuleBodyLimits {
        #if os(macOS)
        return .macOS
        #else
        return .iOS
        #endif
    }

     
     
     
    static let surgeRequestCap = 32 << 20
     
     
     
     
    static let unlimitedDecodeCap = surgeRequestCap
     
     
     
    static let shadowrocketDefault = 128 << 10

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func scriptLimit(_ family: ModuleScriptFamily, maxSize: Int?, phase: ModuleRewritePhase) -> Int? {
        switch family {
        case .surge, .stash:
            let cap = phase == .request ? Self.surgeRequestCap : Int.max
            guard let written = maxSize, written != 0 else { return min(defaultBytes, cap) }
            guard written > 0 else { return phase == .request ? cap : nil }
            return min(written, cap)
        case .shadowrocket:
            guard let written = maxSize else { return Self.shadowrocketDefault }
            return written > 0 ? written : nil
        case .loon, .quantumultX:
            return nil
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    func stepLimit(_ family: ModuleScriptFamily, script: (family: ModuleScriptFamily, limit: Int?)?,
                   phase: ModuleRewritePhase) -> Int? {
        switch family {
        case .surge, .stash:
            if let script, script.family == .surge || script.family == .stash { return script.limit }
            return scriptLimit(.surge, maxSize: nil, phase: phase)
        case .shadowrocket:
            return script?.family == .shadowrocket ? script?.limit : nil
        case .loon, .quantumultX:
            return nil
        }
    }
}

 
 
 
 
 
 
struct ModuleBodyMemoryGuard: Equatable, Sendable {
     
     
     
     
     
     
    var margin: Int64

    static let iOS = ModuleBodyMemoryGuard(margin: ModuleLadderThresholds.iOS.bodies)
}

 
 
enum ModuleBodyWorkingSet {
     
     
     
    static let copies = 3.0
     
     
     
     
    static let jsonPerByte = Double(528 << 10) / 280_000
     
     
     
    static let scriptPerByte = 1.05 * 1_048_576 / 927_000

     
     
     
    static func multiplier(steps: [ModuleBodyStep], script: Bool) -> Double {
        let json = steps.contains { step in
            switch step.work {
            case .json, .jq: return true
            case .replace, .body, .nothing: return false
            }
        }
        return copies + (json ? jsonPerByte : 0) + (script ? scriptPerByte : 0)
    }
}

 
 
struct ModuleBodyPlan: Equatable {
     
     
    let collect: Int?
     
    let steps: [Int?]
     
    let script: Int?
    let workingSet: Double

    init(steps: [ModuleBodyStep], script: ModuleScriptMatch?, phase: ModuleRewritePhase, limits: ModuleBodyLimits) {
        let reader = script.flatMap { $0.script.requiresBody ? $0 : nil }
        let scriptLimit = reader.flatMap { limits.scriptLimit($0.writtenFor, maxSize: $0.script.maxSize, phase: phase) }
        let beside = reader.map { (family: $0.writtenFor, limit: scriptLimit) }
        self.steps = steps.map { limits.stepLimit($0.writtenFor, script: beside, phase: phase) }
        self.script = scriptLimit
        let all = self.steps + (reader == nil ? [] : [scriptLimit])
        collect = all.contains { $0 == nil } ? nil : all.compactMap { $0 }.max()
        workingSet = ModuleBodyWorkingSet.multiplier(steps: steps, script: reader != nil)
    }

     
     
    func split(_ steps: [ModuleBodyStep], bytes: Int) -> (run: [ModuleBodyStep], over: [(step: ModuleBodyStep, limit: Int)]) {
        var run: [ModuleBodyStep] = []
        var over: [(step: ModuleBodyStep, limit: Int)] = []
        for (step, limit) in zip(steps, self.steps) {
            if let limit, bytes > limit { over.append((step, limit)) } else { run.append(step) }
        }
        return (run, over)
    }
}

 
enum ModuleBodySkip: Error, Equatable, Sendable {
    case tooManyAtOnce(Int)
    case declaredTooLarge(Int64, Int)
    case grewTooLarge(Int)
     
    case spillFailed
    case decodedTooLarge(Int)
    case notDecodable(String)
    case notText
    case bodiesStopped
    case scriptsStopped
     
     
    case partialContent
     
     
     
    case memory(needed: Int64, others: Int64, available: Int64, margin: Int64)

     
    var isOverALimit: Bool {
        switch self {
        case .declaredTooLarge, .grewTooLarge, .decodedTooLarge: return true
        default: return false
        }
    }

    var description: String {
        switch self {
        case .tooManyAtOnce(let count): return "\(count) bodies are already held"
        case .declaredTooLarge(let length, let limit): return "Content-Length \(length) is over the \(limit)-byte limit"
        case .grewTooLarge(let limit): return "the body grew past the \(limit)-byte limit"
        case .spillFailed: return "the disk would not hold it while it was collected"
        case .decodedTooLarge(let limit): return "it decodes past the \(limit)-byte limit"
        case .notDecodable(let why): return "its encoding cannot be read here (\(why))"
        case .notText: return "it is not UTF-8 text"
        case .bodiesStopped: return "body changes are paused for memory"
        case .scriptsStopped: return "scripts are paused"
        case .partialContent: return "it is a part of a body (206 or Content-Range), which is never rewritten"
        case .memory(let needed, let others, let available, let margin):
            let mib = { (bytes: Int64) in String(format: #"%.1f MiB"#, Double(bytes) / 1_048_576) }
            let beside = others > 0 ? #" beside the \#(mib(others)) the other bodies take"# : ""
            return #"working on it takes about \#(mib(needed))\#(beside), and \#(mib(available)) is left, \#(mib(margin)) of it kept free"#
        }
    }
}

 
 
 
 
final class ModuleBodyBudget {
    let limits: ModuleBodyLimits
    private let metrics: ModuleEngineMetrics
    private let spillDirectory: URL?
     
     
    private let availableMemory: () -> Int64?
    private(set) var active = 0
     
    private(set) var reserved: Int64 = 0

    init(limits: ModuleBodyLimits, metrics: ModuleEngineMetrics, spillDirectory: URL?,
         availableMemory: @escaping () -> Int64? = ModuleMemoryProbe.available) {
        self.limits = limits
        self.metrics = metrics
        self.spillDirectory = spillDirectory
        self.availableMemory = availableMemory
    }

     
     
     
     
     
     
    func begin(declaredLength: Int64?, limit: Int?, workingSet: Double = ModuleBodyWorkingSet.copies,
               atOnce: Int? = nil) -> Result<ModuleBodyCollection, ModuleBodySkip> {
        if let limit, let declaredLength, declaredLength > Int64(limit) {
            return .failure(metrics.skipped(.declaredTooLarge(declaredLength, limit)))
        }
        if let atOnce, active >= atOnce { return .failure(metrics.skipped(.tooManyAtOnce(active))) }
        let slot = ModuleBodySlot(budget: self, workingSet: workingSet)
         
        if let why = memoryRefusal(slot, growingTo: max(0, declaredLength ?? 0)) { return .failure(metrics.skipped(why)) }
        active += 1
        metrics.update { $0.bodyCollectionsTotal += 1 }
        return .success(ModuleBodyCollection(limit: limit, slot: slot, spillAbove: limits.spillAbove,
                                              spillDirectory: spillDirectory, metrics: metrics))
    }

     
     
     
    fileprivate func memoryRefusal(_ slot: ModuleBodySlot, growingTo bytes: Int64) -> ModuleBodySkip? {
        guard let memoryGuard = limits.memoryGuard, let available = availableMemory() else { return nil }
        let others = reserved - slot.reserved
        let needed = slot.workingSet(of: bytes)
        guard available - others - needed < memoryGuard.margin else { return nil }
        return .memory(needed: needed, others: others, available: available, margin: memoryGuard.margin)
    }

     
     
    fileprivate func decodeAllowance(_ slot: ModuleBodySlot, raw: Int) -> Int? {
        guard let memoryGuard = limits.memoryGuard, let available = availableMemory() else { return nil }
        let left = available - (reserved - slot.reserved) - memoryGuard.margin - Int64(raw)
        return left > 0 ? Int(Double(left) / slot.workingSet) : 0
    }

     
     
     
     
    func jsonAllowance(_ held: ModuleHeldBody, bytes: Int) -> Int? {
        guard let slot = held.slot, let memoryGuard = limits.memoryGuard, let available = availableMemory() else { return nil }
        let left = available - memoryGuard.margin - (reserved - slot.reserved)
            - Int64((Double(bytes) * ModuleBodyWorkingSet.copies).rounded(.up))
        return Int(max(0, left))
    }

     
    fileprivate func memorySkip(_ slot: ModuleBodySlot, bytes: Int64) -> ModuleBodySkip {
        let available = availableMemory() ?? 0
        return .memory(needed: slot.workingSet(of: bytes), others: reserved - slot.reserved, available: available,
                       margin: limits.memoryGuard?.margin ?? 0)
    }

    fileprivate func reserve(_ change: Int64) {
        reserved += change
    }

    fileprivate func giveBack(reserved bytes: Int64) {
        active -= 1
        reserved -= bytes
    }

     
     
    func decode(_ body: Data, coding: ModuleContentCoding, maximumOutputLength: Int) -> Result<Data, ModuleBodySkip> {
        do {
            let decoded = try ModuleBodyDecoder.decode(body, coding: coding, maximumOutputLength: maximumOutputLength)
            guard !decoded.outputLimitExceeded else { return .failure(metrics.skipped(.decodedTooLarge(max(0, maximumOutputLength)))) }
            return .success(decoded.data)
        } catch let error as ModuleBodyDecoderError {
            return .failure(metrics.skipped(.notDecodable(error.reason)))
        } catch {
            return .failure(metrics.skipped(.notDecodable("\(error)")))
        }
    }

     
     
     
     
    func decode(_ held: ModuleHeldBody, _ body: Data, coding: ModuleContentCoding, cap: Int) -> Result<Data, ModuleBodySkip> {
        guard coding != .identity, let slot = held.slot else { return decode(body, coding: coding, maximumOutputLength: cap) }
        let allowance = decodeAllowance(slot, raw: body.count)
        guard let allowance, allowance < cap else {
            let decoded = decode(body, coding: coding, maximumOutputLength: cap)
            if case .success(let data) = decoded { slot.hold(raw: body.count, decoded: data.count) }
            return decoded
        }
        do {
            let decoded = try ModuleBodyDecoder.decode(body, coding: coding, maximumOutputLength: allowance)
            guard !decoded.outputLimitExceeded else {
                return .failure(metrics.skipped(memorySkip(slot, bytes: Int64(allowance) + 1)))
            }
            slot.hold(raw: body.count, decoded: decoded.data.count)
            return .success(decoded.data)
        } catch let error as ModuleBodyDecoderError {
            return .failure(metrics.skipped(.notDecodable(error.reason)))
        } catch {
            return .failure(metrics.skipped(.notDecodable("\(error)")))
        }
    }
}

extension ModuleEngineMetrics {
     
    fileprivate func skipped(_ why: ModuleBodySkip) -> ModuleBodySkip {
        update {
            $0.bodySkippedTotal += 1
            if why.isOverALimit { $0.bodyLimitExceeded += 1 }
        }
        return why
    }
}

 
 
 
fileprivate final class ModuleBodySlot {
    private weak var budget: ModuleBodyBudget?
     
    let workingSet: Double
     
    fileprivate private(set) var reserved: Int64 = 0
    private var given = false

    fileprivate init(budget: ModuleBodyBudget, workingSet: Double) {
        self.budget = budget
        self.workingSet = max(1, workingSet)
    }

    fileprivate func workingSet(of bytes: Int64) -> Int64 {
        Int64((Double(max(0, bytes)) * workingSet).rounded(.up))
    }

     
    fileprivate func memoryRefusal(growingTo bytes: Int64) -> ModuleBodySkip? {
        guard !given else { return nil }
        return budget?.memoryRefusal(self, growingTo: bytes)
    }

     
    fileprivate func hold(_ bytes: Int64) {
        set(workingSet(of: bytes))
    }

     
    fileprivate func hold(raw: Int, decoded: Int) {
        set(Int64(raw) + workingSet(of: Int64(decoded)))
    }

    private func set(_ bytes: Int64) {
        guard !given else { return }
        budget?.reserve(bytes - reserved)
        reserved = bytes
    }

    func giveBack() {
        guard !given else { return }
        given = true
        budget?.giveBack(reserved: reserved)
        reserved = 0
    }
}

 
 
 
final class ModuleHeldBody {
    private var bytes: Data?
    private var giveBack: (() -> Void)?
     
    fileprivate let slot: ModuleBodySlot?

    fileprivate init(_ bytes: Data, slot: ModuleBodySlot?, giveBack: @escaping () -> Void) {
        self.bytes = bytes
        self.slot = slot
        self.giveBack = giveBack
    }

     
    func take() -> Data {
        defer { bytes = nil }
        return bytes ?? Data()
    }

    var isReleased: Bool { giveBack == nil }

    func release() {
        bytes = nil
        let pending = giveBack
        giveBack = nil
        pending?()
    }

    deinit { release() }
}

 
enum ModuleBodyCollected {
    case memory(Data)
     
    case spilled(ModuleSpillReader)
}

 
 
final class ModuleSpillReader {
    static let piece = 64 * 1024
     
    let count: Int
    private var handle: FileHandle?
    private let file: URL
    private var offset = 0
     
    private(set) var largestRead = 0

    fileprivate init(handle: FileHandle, file: URL, count: Int) {
        self.handle = handle
        self.file = file
        self.count = count
    }

    deinit { close() }

     
     
     
     
    func next() -> Data? {
        guard let handle else { return nil }
        guard offset < count else { return Data() }
        let wanted = min(Self.piece, count - offset)
        let read: Data? = autoreleasepool {
            do {
                if offset == 0 { try handle.seek(toOffset: 0) }
                guard let data = try handle.read(upToCount: wanted), data.count == wanted else { return nil }
                return Data(data)
            } catch {
                return nil
            }
        }
        guard let read else { return nil }
        offset += wanted
        largestRead = max(largestRead, wanted)
        return read
    }

    func close() {
        guard let handle else { return }
        self.handle = nil
        try? handle.close()
        try? FileManager.default.removeItem(at: file)
    }
}

 
final class ModuleBodyCollection {
     
    let limit: Int?
    private let slot: ModuleBodySlot
    private(set) var count = 0
    private let spillAbove: Int?
    private let spillDirectory: URL?
    private let metrics: ModuleEngineMetrics
    private var release: (() -> Void)?
    private var memory = Data()
     
    private var spillTried = false
    private var spillFile: URL?
    private var spillHandle: FileHandle?
     
    private var spilled = 0
     
     
    private(set) var refusal: ModuleBodySkip?

    fileprivate init(limit: Int?, slot: ModuleBodySlot, spillAbove: Int?, spillDirectory: URL?, metrics: ModuleEngineMetrics) {
        self.limit = limit
        self.slot = slot
        self.spillAbove = spillAbove
        self.spillDirectory = spillDirectory
        self.metrics = metrics
        release = { slot.giveBack() }
    }

    deinit { end() }

     
     
     
    func append<Bytes: DataProtocol>(_ data: Bytes) -> Bool {
        guard release != nil, refusal == nil else { return false }
        if let limit, count + data.count > limit { return refuse(.grewTooLarge(limit)) }
         
        if let why = slot.memoryRefusal(growingTo: Int64(count + data.count)) { return refuse(why) }
        if spillHandle == nil, !spillTried, let threshold = spillAbove, let directory = spillDirectory, memory.count + data.count > threshold {
            spillTried = true
            startSpilling(in: directory)
        }
        if let spillHandle {
            do {
                try spillHandle.write(contentsOf: data)
            } catch {
                return refuse(.spillFailed)
            }
            spilled += data.count
            count += data.count
            slot.hold(Int64(count))
            metrics.update { $0.bodyCollectBytesTotal += data.count }
        } else {
            memory.append(contentsOf: data)
            count += data.count
            slot.hold(Int64(count))
            metrics.update {
                $0.bodyCollectBytesTotal += data.count
                $0.bodyCollectBytes += data.count
                $0.bodyCollectBytesPeak = max($0.bodyCollectBytesPeak, $0.bodyCollectBytes)
            }
        }
        return true
    }

     
     
     
     
    func finish() -> Data? {
        guard refusal == nil else { return nil }
        return giveBack()
    }

     
     
    func abandon() -> Data? { giveBack() }

     
     
     
     
     
    func giveWay() -> ModuleBodyCollected? {
        guard release != nil else { return nil }
        guard let handle = spillHandle, let file = spillFile else {
            let bytes = memory
            end()
            return .memory(bytes)
        }
         
        spillHandle = nil
        spillFile = nil
        let reader = ModuleSpillReader(handle: handle, file: file, count: spilled)
        end()
        return .spilled(reader)
    }

     
    func discard() { end() }

     
     
     
     
     
     
    func finishHeld() -> ModuleHeldBody? {
        guard refusal == nil, let slot = release else { return nil }
        let bytes: Data
        if spillHandle == nil {
            bytes = memory
        } else {
            guard let read = spilledBytes() else {
                end()
                return nil
            }
            bytes = read
            metrics.update {
                $0.bodyCollectBytes += read.count
                $0.bodyCollectBytesPeak = max($0.bodyCollectBytesPeak, $0.bodyCollectBytes)
            }
        }
         
        release = nil
        memory = Data()
        try? spillHandle?.close()
        spillHandle = nil
        if let spillFile { try? FileManager.default.removeItem(at: spillFile) }
        spillFile = nil
        let metrics = self.metrics
        let counted = bytes.count
        return ModuleHeldBody(bytes, slot: self.slot) {
            metrics.update { $0.bodyCollectBytes -= counted }
            slot()
        }
    }

    private func refuse(_ why: ModuleBodySkip) -> Bool {
        refusal = metrics.skipped(why)
        return false
    }

    private func giveBack() -> Data? {
        guard release != nil else { return nil }
        let bytes = spillHandle == nil ? memory : spilledBytes()
        end()
        return bytes
    }

     
     
    private func startSpilling(in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString + ".body")
        let descriptor = open(file.path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        do {
            try handle.write(contentsOf: memory)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: file)
            return
        }
        spillFile = file
        spillHandle = handle
        spilled = memory.count
        metrics.update { $0.bodyCollectBytes -= memory.count }
        memory = Data()
    }

    private func spilledBytes() -> Data? {
        guard let spillHandle else { return nil }
        do {
            try spillHandle.seek(toOffset: 0)
            let bytes = try spillHandle.read(upToCount: spilled) ?? Data()
            return bytes.count == spilled ? bytes : nil
        } catch {
            return nil
        }
    }

    private func end() {
        guard let release else { return }
        self.release = nil
        metrics.update { $0.bodyCollectBytes -= memory.count }
        memory = Data()
        try? spillHandle?.close()
        spillHandle = nil
        if let spillFile { try? FileManager.default.removeItem(at: spillFile) }
        spillFile = nil
        release()
    }
}
#endif
