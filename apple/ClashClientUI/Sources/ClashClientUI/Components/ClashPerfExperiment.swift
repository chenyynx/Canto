import Foundation

 
 
 
 
 
 
public enum ClashPerfExperiment {
     
     
     
     
     
     
     
     
     
    public static let suppressesGlass = ProcessInfo.processInfo
        .arguments.contains("--clash-perf-no-glass")

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static let freezesTrafficFigures = ProcessInfo.processInfo
        .arguments.contains("--clash-perf-freeze-traffic")

     
     
     
     
     
     
     
     
    public static let suppressesDurationTick = ProcessInfo.processInfo
        .arguments.contains("--clash-perf-no-duration-tick")
}
