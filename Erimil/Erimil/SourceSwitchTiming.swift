//
//  SourceSwitchTiming.swift
//  Erimil
//
//  S050: Timing instrumentation for source switch pipeline (#93)
//
//  Usage:
//    SourceSwitchTiming.start("click")       // T0
//    SourceSwitchTiming.mark("callback")      // T1
//    SourceSwitchTiming.mark("select.start")  // T2
//    SourceSwitchTiming.mark("select.done")   // T3
//    SourceSwitchTiming.mark("load.start")    // T4
//    SourceSwitchTiming.mark("load.done")     // T5 — also prints summary
//
//  Filter in Console.app: [TIMING]
//

import Foundation
import os

struct SourceSwitchTiming {
    private static let logger = Logger(subsystem: "com.zembutsu.erimil", category: "timing")
    
    /// Absolute time of the first start() call in the current pipeline
    private static var t0: CFAbsoluteTime = 0
    /// Previous mark time for delta calculation
    private static var tPrev: CFAbsoluteTime = 0
    /// Collected marks for summary
    private static var marks: [(label: String, absolute: CFAbsoluteTime)] = []
    
    /// Begin a new timing pipeline
    static func start(_ label: String) {
        let now = CFAbsoluteTimeGetCurrent()
        t0 = now
        tPrev = now
        marks = [(label, now)]
        counters = [:]
        logger.info("[TIMING] ▶ \(label) (t=0ms)")
    }
    
    /// Record a checkpoint in the pipeline
    static func mark(_ label: String) {
        let now = CFAbsoluteTimeGetCurrent()
        let fromStart = (now - t0) * 1000
        let delta = (now - tPrev) * 1000
        tPrev = now
        marks.append((label, now))
        logger.info("[TIMING] · \(label): \(String(format: "%.1f", fromStart))ms (Δ\(String(format: "%.1f", delta))ms)")
    }
    
    /// Track repeated evaluations (e.g., body re-evaluation count)
    private static var counters: [String: Int] = [:]
    static func count(_ label: String) {
        guard t0 > 0 else { return }  // No active pipeline
        let now = CFAbsoluteTimeGetCurrent()
        let fromStart = (now - t0) * 1000
        let n = (counters[label] ?? 0) + 1
        counters[label] = n
        logger.info("[TIMING] # \(label) ×\(n): \(String(format: "%.1f", fromStart))ms")
    }
    
    /// Record final checkpoint and print summary
    static func end(_ label: String) {
        let now = CFAbsoluteTimeGetCurrent()
        let total = (now - t0) * 1000
        let delta = (now - tPrev) * 1000
        marks.append((label, now))
        
        // Summary
        logger.info("[TIMING] ■ \(label): \(String(format: "%.1f", total))ms total (Δ\(String(format: "%.1f", delta))ms)")
        
        // Print breakdown
        var summary = "[TIMING] ── Summary ──"
        for i in 1..<marks.count {
            let seg = (marks[i].absolute - marks[i-1].absolute) * 1000
            summary += "\n  \(marks[i-1].label) → \(marks[i].label): \(String(format: "%.1f", seg))ms"
        }
        logger.info("\(summary)")
        
        // Reset
        marks = []
    }
}
