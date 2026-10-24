import Foundation

 
 
 
 
 

 
 
 
 
 
 
 
 
 
 
struct ModuleRegexDeadline {
     
    static let readingSpacing: UInt64 = 1_000_000
    private let limit: UInt64
    private let started: UInt64
    private var lastReading: UInt64

    init(_ deadline: TimeInterval) {
        limit = UInt64(max(0, deadline) * 1_000_000_000)
        started = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        lastReading = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

     
    mutating func isPast() -> Bool {
        let uptime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        guard uptime &- lastReading >= Self.readingSpacing else { return false }
        lastReading = uptime
        return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) &- started > limit
    }
}
