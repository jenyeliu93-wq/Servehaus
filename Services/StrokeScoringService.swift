//
//  StrokeScoringService.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/21/25.
//

// Services/Analysis/StrokeScoringService.swift
import Foundation


internal typealias PublicStrokeType = StrokeType

public enum StrokeScoringService {
    
    /// Level 1: Per-phase scoring handled in PoseFeatureExtractor
    /// Level 2: Per-stroke aggregation computed here via scoreStroke()
    /// Level 3: Video-level aggregation averaging across strokes
    
    /// Scores a single stroke from its phases and returns a StrokeScore.
    internal static func scoreStroke(from stroke: StrokeSegment) -> StrokeScore {
        let phases = stroke.phases
        let dict = Dictionary(uniqueKeysWithValues: phases.map { ($0.phase, $0) })

        let coil = dict[.coil]?.score ?? 0
        let accel = dict[.acceleration]?.score ?? 0
        let impact = dict[.impact]?.score ?? 0
        let follow = dict[.followThrough]?.score ?? 0
        let split = dict[.splitStep]?.score ?? 0

        let total = (coil * 0.25 + accel * 0.25 + impact * 0.20 + follow * 0.20 + split * 0.10)

        let completeness = Double(phases.filter { $0.score > 0 }.count) / 5.0
        let avgConfidence = phases.map { $0.confidence }.reduce(0, +) / Double(max(phases.count, 1))
        let weightedTotal = total * completeness * avgConfidence

        let subMetrics: [String: Double] = [
            "coil": coil,
            "acceleration": accel,
            "impact": impact,
            "followThrough": follow,
            "splitStep": split,
            "completeness": completeness,
            "confidence": avgConfidence
        ]

        return StrokeScore(
            strokeId: stroke.id,
            strokeType: stroke.type,
            phaseScores: phases,
            totalScore: weightedTotal,
            subMetrics: subMetrics
        )
    }
    
    /// Scores an array of StrokeSegment grouped per stroke.
    /// For each stroke:
    /// - Computes per-stroke StrokeScore using scoreStroke()
    /// Then aggregates scores across strokes:
    /// - If ≥3 strokes, drop highest and lowest total scores, then average per hand.
    /// - Else average all per hand.
    /// Returns VideoScore with overall score.
    internal static func scoreStrokes(_ strokes: [StrokeSegment]) -> VideoScore {
        let strokeScores = strokes.map { scoreStroke(from: $0) }
        
        // Separate scores by stroke type
        let forehandScores = strokeScores.filter { $0.strokeType == .forehand }
        let backhandScores = strokeScores.filter { $0.strokeType == .backhand }
        
        let forehandTotals = forehandScores.map { $0.totalScore }
        let backhandTotals = backhandScores.map { $0.totalScore }
        
        // Compute per-hand averages with trimming if >=3
        let forehandAvg = trimmedAverage(forehandTotals)
        let backhandAvg = trimmedAverage(backhandTotals)
        
        // Compute overall as 0.5 * (forehandAvg + backhandAvg) if both exist, else average of existing
        let overall: Double
        if !forehandTotals.isEmpty && !backhandTotals.isEmpty {
            overall = 0.5 * (forehandAvg + backhandAvg)
        } else if !forehandTotals.isEmpty {
            overall = forehandAvg
        } else if !backhandTotals.isEmpty {
            overall = backhandAvg
        } else {
            overall = 0
        }
        
        return VideoScore(
            strokes: strokeScores,
            forehandAvg: forehandTotals.isEmpty ? nil : forehandAvg,
            backhandAvg: backhandTotals.isEmpty ? nil : backhandAvg,
            overall: overall
        )
    }
    
    /// Helper method to compute average of an array of Doubles.
    /// Returns 0 if array is empty.
    internal static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sum = values.reduce(0, +)
        return sum / Double(values.count)
    }
    
    /// Helper method to compute trimmed average by dropping highest and lowest values.
    /// If less than 3 values, returns average of all.
    internal static func trimmedAverage(_ values: [Double]) -> Double {
        guard values.count >= 3 else { return average(values) }
        let sortedValues = values.sorted()
        let trimmed = sortedValues[1..<(sortedValues.count - 1)]
        return average(Array(trimmed))
    }
}
