import Foundation
import Clash
extension PhysicalInterfaceInventory {
     
     
    final class Iterator: NSObject, ClashNetworkInterfaceIteratorProtocol {
        private var remaining: ArraySlice<Record>
        private let count: Int32

        init(_ records: [Record]) {
            remaining = records[...]
            count = Int32(clamping: records.count)
        }

        func len() -> Int32 { count }

        func hasNext() -> Bool { !remaining.isEmpty }

        func next() -> ClashNetworkInterface? {
            guard let record = remaining.popFirst() else { return nil }
            let interface = ClashNetworkInterface()
            interface.name = record.name
            interface.index = Int32(bitPattern: record.index)
            interface.mtu = record.mtu
            interface.flags = record.flags.rawValue
            interface.type = record.type.rawValue
            interface.metered = record.metered
            interface.addresses = Strings(record.addresses)
            return interface
        }

        final class Strings: NSObject, ClashStringIteratorProtocol {
            private var remaining: ArraySlice<String>
            private let count: Int32

            init(_ values: [String]) {
                remaining = values[...]
                count = Int32(clamping: values.count)
            }

            func len() -> Int32 { count }
            func hasNext() -> Bool { !remaining.isEmpty }
            func next() -> String { remaining.popFirst() ?? "" }
        }
    }

}
