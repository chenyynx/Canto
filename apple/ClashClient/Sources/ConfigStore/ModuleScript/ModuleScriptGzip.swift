#if os(iOS) || os(macOS)
import Compression
import Foundation

 
 
 
enum ModuleScriptGzip {
    enum Failure: Error, Equatable, CustomStringConvertible {
        case notGzip
        case corrupt
        case tooLarge(Int)

        var description: String {
            switch self {
            case .notGzip: return #"not gzip data"#
            case .corrupt: return #"the gzip data is damaged or cut short"#
            case .tooLarge(let limit): return #"the output passes \#(limit) bytes"#
            }
        }
    }

    static func ungzip(_ input: Data, limit: Int) -> Result<Data, Failure> {
        let bytes = [UInt8](input)
         
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return .failure(.notGzip) }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {  
            guard index + 2 <= bytes.count else { return .failure(.corrupt) }
            let extra = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + extra
        }
        for field: UInt8 in [0x08, 0x10] where flags & field != 0 {  
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 }  
        guard index <= bytes.count - 8 else { return .failure(.corrupt) }
        return inflate(bytes[index..<(bytes.count - 8)], limit: limit)
    }

    private static func inflate(_ deflated: ArraySlice<UInt8>, limit: Int) -> Result<Data, Failure> {
        let chunk = 32 << 10
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { destination.deallocate() }
        return deflated.withUnsafeBufferPointer { source -> Result<Data, Failure> in
            guard let base = source.baseAddress else { return .failure(.corrupt) }
            var stream = compression_stream(dst_ptr: destination, dst_size: chunk, src_ptr: base, src_size: 0, state: nil)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
            else { return .failure(.corrupt) }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = base
            stream.src_size = source.count
            var output = Data()
            while true {
                stream.dst_ptr = destination
                stream.dst_size = chunk
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunk - stream.dst_size
                if produced > 0 {
                     
                     
                    guard output.count + produced <= limit else { return .failure(.tooLarge(limit)) }
                    output.append(destination, count: produced)
                }
                if status == COMPRESSION_STATUS_END { return .success(output) }
                guard status == COMPRESSION_STATUS_OK else { return .failure(.corrupt) }
                 
                 
                if produced == 0, stream.src_size == 0 { return .failure(.corrupt) }
            }
        }
    }
}
#endif
