//
//  MotionFeaturePipeline.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/27/25.
//

import Foundation
import CoreMedia

/// A unified and modernized motion analysis engine designed to process motion data in a clean and extensible manner.
/// Integrates seamlessly with `StrokeAnalysisPipeline`.

public struct MotionFeaturePipeline {

    public static func segmentStrokes(from motionPoints: [MotionPoint]) async -> [StrokeSegment] {
        let pipeline = MotionFeaturePipeline()
        do {
            return try await pipeline.processMotionData(motionPoints)
        } catch {
            print("⚠️ MotionFeaturePipeline error: \(error)")
            return []
        }
    }

    // MARK: - Public Interface

    /// Processes an array of MotionPoint objects through the full pipeline asynchronously.
    /// - Parameter motionPoints: The array of MotionPoint objects representing the motion input.
    /// - Returns: An array of detected stroke segments, each with nested phase segments.
    public func processMotionData(_ motionPoints: [MotionPoint]) async throws -> [StrokeSegment] {
        // No need to compute metrics; PoseAnalysisService already produces [MotionPoint]
        // Segment and detect strokes (returns [StrokeSegment] with nested [PhaseSegment])
        let segments = await segmentAndDetectStrokes(from: motionPoints)
        return segments
    }

    // MARK: - Metrics Computation (Per-frame Metrics)

    // The computeMetrics(from:) method is no longer needed; input is already [MotionPoint] from PoseAnalysisService.

    // MARK: - Segmentation & Stroke Detection

    /// Segments the motion data and detects individual strokes.
    /// - Parameter motionPoints: The per-frame computed motion points.
    /// - Returns: Detected stroke segments.
    private func segmentAndDetectStrokes(from motionPoints: [MotionPoint]) async -> [StrokeSegment] {
        // Detect strokes based on energy peaks and valleys, assign stroke types, and segment subphases.
        // 1. Find baseline energy (median or low quantile).
        let energyValues = motionPoints.compactMap { $0.energyRearHybrid }
        guard !energyValues.isEmpty else { return [] }
        let sortedEnergy = energyValues.sorted()
        let baselineEnergy = sortedEnergy[Int(Double(sortedEnergy.count) * 0.2)]
        let minValley = baselineEnergy * 0.25
        // 2. Find peaks (local maxima in energy above threshold), valleys (local minima below minValley)
        var peaks: [Int] = []
        var valleys: [Int] = []
        let win = 2
        for i in win..<(motionPoints.count-win) {
            let e = energyValues[i]
            let isPeak = (e > energyValues[i-1]) && (e > energyValues[i+1]) && (e > baselineEnergy*1.3)
            let isValley = (e < energyValues[i-1]) && (e < energyValues[i+1]) && (e < minValley)
            if isPeak { peaks.append(i) }
            if isValley { valleys.append(i) }
        }
        // 3. Pair valleys and peaks to define stroke segments (valley -> peak -> valley)
        var detectedSegments: [(start: Int, end: Int)] = []
        var i = 0
        while i < valleys.count-1 {
            let vStart = valleys[i]
            // Find next peak after valley
            let nextPeak = peaks.first(where: { $0 > vStart && $0 < valleys[i+1] })
            if let _ = nextPeak {
                // Segment: vStart to valleys[i+1]
                detectedSegments.append((start: vStart, end: valleys[i+1]))
            }
            i += 1
        }
        // 4. For each detected segment, assign stroke type and segment subphases
        var outputSegments: [StrokeSegment] = []
        // --- New refined stroke-type detection logic with persistence and lockout ---
        var lastType: StrokeType? = nil
//        var persistenceCount = 0
//        var lockoutCounter = 0
//        let persistenceFrames = 5
//        let lockoutFrames = 9 // ~0.3s at 30fps
        for seg in detectedSegments {
            let metricsInSegment = Array(motionPoints[seg.start...seg.end])
            // Sort metrics by time ascending
            let sortedMetrics = metricsInSegment.sorted { $0.time < $1.time }
            guard let first = sortedMetrics.first, let last = sortedMetrics.last, first.time <= last.time else {
                print("⚠️ Skipped invalid segment due to reversed or missing times")
                continue
            }
            // Use helper to classify stroke type with persistence/lockout logic
            let strokeType = classifyStrokeType(
                metrics: sortedMetrics,
                lastType: lastType
            )
            lastType = strokeType
            // Segment subphases
            let subphases = segmentSubphases(for: strokeType, from: sortedMetrics)
            let strokeUUID = UUID()
            // Assign strokeId to each phase segment
            let phaseSegments = subphases.map { phaseSeg -> PhaseSegment in
                return PhaseSegment(
                    phase: phaseSeg.phase,
                    confidence: phaseSeg.confidence,
                    frames: [phaseSeg.frames.first!], // Will fix below
                    metrics: [:],
                    score: phaseSeg.score,
                    formula: ""
                )
            }
            let confidence = computeStrokeConfidence(
                from: sortedMetrics,
                phaseSegments: phaseSegments,
                baselineEnergy: baselineEnergy
            )
            let strokeSegment = StrokeSegment(
                id: strokeUUID,
                type: strokeType,
                timeRange: first.time...last.time,
                frames: sortedMetrics,
                phases: phaseSegments,
                aggregates: [:],
                confidence: confidence
            )
            outputSegments.append(strokeSegment)
        }
        return outputSegments
    }

    // MARK: - Type Classification
    // (Removed: Obsolete StrokeClassification and classifyStrokeTypes function.)

    // MARK: - Split Step Detection Logic

    /// Detects if the given motion point indicates a Split Step posture, using proxy metrics instead of raw joints.
    /// Split Step → large stance width (hip/shoulder span widened) + low wrist height + low energy.
    private func detectSplitStep(in metric: MotionPoint) -> Bool {
        // Thresholds tuned for normalized metric scale (0–1)
        let minHipSpan: CGFloat = 0.25
        let minShoulderSpan: CGFloat = 0.2
        let maxWristHeight: CGFloat = -0.05  // low wrist relative to shoulder
        let maxEnergy: CGFloat = 0.2         // relaxed / recovery posture

        // Proxy indicators for stance and posture symmetry
        let stanceWide = metric.hipSpan > minHipSpan && metric.shoulderSpan > minShoulderSpan
        let handsLow = metric.wristHeightRel < maxWristHeight
        let lowEnergy = metric.energyRearHybrid < maxEnergy

        return stanceWide && handsLow && lowEnergy
    }

    // MARK: - Subphase Segmentation for Forehand (FH) and Backhand (BH)

    /// Segments subphases for a given stroke type (Forehand or Backhand) based on per-frame metrics.
    /// Uses differentiated rules for FH and BH, mirroring thresholds for wristXOffsetRel and rotation direction.
    /// - Parameters:
    ///   - strokeType: The type of stroke (.forehand or .backhand).
    ///   - metrics: The per-frame metrics within the stroke segment.
    /// - Returns: An array of PhaseSegment objects representing subphases with associated metadata.
    private func segmentSubphases(for strokeType: StrokeType, from metrics: [MotionPoint]) -> [PhaseSegment] {
        // Anchor + Smooth + Sequential: produce at most one of each subphase in order
        guard metrics.count > 5 else { return [] }
        
        // Convenience accessors
        let energy = metrics.map { $0.energyRearHybrid }
        let rot = metrics.map { $0.rotSign }
        let shoulderCoil = metrics.map { $0.shoulderCoilFactor }
        let wristX = metrics.map { $0.wristXOffsetRel }
        let wristH = metrics.map { $0.wristHeightRel }
        
        // Thresholds
        let coilThreshold: CGFloat = -0.08
        let impactNeutralRot: CGFloat = 0.10
        let impactNeutralShoulder: CGFloat = 0.05
        let impactWristMid: CGFloat = 0.30
        let followWristFH: CGFloat = 0.20
        let followWristBH: CGFloat = -0.20
        let lowEnergy: CGFloat = 0.20
        
        // Helpers
        func isLocalPeak(_ arr: [CGFloat], _ i: Int) -> Bool {
            guard i > 0 && i < arr.count-1 else { return false }
            return arr[i] > arr[i-1] && arr[i] > arr[i+1]
        }
        func isImpact(_ i: Int) -> Bool {
            guard i > 0 && i < metrics.count-1 else { return false }
            let ePeak = isLocalPeak(energy, i)
            let rotNeutral = abs(rot[i]) < impactNeutralRot || rot[i+1] < rot[i] // decelerating
            let shoulderNeutral = abs(shoulderCoil[i]) < impactNeutralShoulder
            let wristNearMid = abs(wristX[i]) < impactWristMid
            return ePeak && rotNeutral && shoulderNeutral && wristNearMid
        }
        func rotationFlipsPositive(between lo: Int, _ hi: Int) -> Int? {
            guard hi - lo >= 1 else { return nil }
            for i in max(1, lo)...min(rot.count-1, hi) {
                if rot[i-1] <= 0 && rot[i] > 0 { return i }
            }
            return nil
        }
        func makePhase(_ phase: StrokeSubPhase, _ range: ClosedRange<Int>) -> PhaseSegment {
            let frames = Array(metrics[range])
            // Confidence source per phase
            let confValues: [CGFloat]
            switch phase {
            case .coil: confValues = frames.map { $0.shoulderCoilFactor }
            case .acceleration:
                // use energy slope magnitude
                var deltas: [CGFloat] = []
                for i in range.lowerBound..<range.upperBound {
                    deltas.append(energy[i+1] - energy[i])
                }
                confValues = deltas.map { abs($0) }
            case .impact: confValues = [metrics[range.lowerBound].energyRearHybrid]
            case .followThrough:
                var deltas: [CGFloat] = []
                for i in range.lowerBound..<range.upperBound {
                    deltas.append(energy[i] - energy[i+1]) // decay
                }
                confValues = deltas.map { max(0, $0) }
            case .splitStep:
                confValues = frames.map { (1 - abs($0.wristXOffsetRel)) }
            }
            let conf = confValues.isEmpty ? 0.6 : computeConfidence(from: confValues)
            // Score proxy per phase
            let score: Double
            switch phase {
            case .coil:
                score = Double(frames.map { -$0.shoulderCoilFactor }.max() ?? 0)
            case .acceleration:
                score = Double(frames.map { $0.energyRearHybrid }.last ?? 0)
            case .impact:
                score = Double(frames.map { $0.energyRearHybrid }.max() ?? 0)
            case .followThrough:
                score = Double(frames.map { $0.energyRearHybrid }.first ?? 0)
            case .splitStep:
                score = Double(frames.map { $0.hipSpan + $0.shoulderSpan }.max() ?? 0)
            }
            return PhaseSegment(
                phase: phase,
                confidence: conf,
                frames: frames,
                metrics: [:],
                score: score,
                formula: ""
            )
        }
        
        // 1) Find Impact anchor (fallback to strongest energy peak if none matches neutrality constraints)
        var impactIdx: Int? = nil
        // search whole window for a valid impact
        for i in 1..<(metrics.count-1) {
            if isImpact(i) { impactIdx = i; break }
        }
        if impactIdx == nil {
            // fallback to absolute max energy index
            if let maxIdx = energy.enumerated().max(by: { $0.element < $1.element })?.offset {
                impactIdx = maxIdx
            }
        }
        guard let kImpact = impactIdx else { return [] }
        
        // Build result (keep strict order)
        var result: [PhaseSegment] = []
        
        // 2) COIL — search backward up to ~20 frames
        let coilSearchLo = max(0, kImpact - 20)
        var coilStart: Int? = nil
        var coilEnd: Int? = nil
        for i in stride(from: kImpact-1, through: coilSearchLo, by: -1) {
            let coilCond = (shoulderCoil[i] < coilThreshold && rot[i] < 0 && wristH[i] < -0.1)
            let wristSideOK: Bool = {
                switch strokeType {
                case .forehand: return wristX[i] > 0.1
                case .backhand: return wristX[i] < -0.1
                }
            }()
            if coilCond && wristSideOK {
                coilEnd = i
                // expand further back while condition roughly holds to get a start
                var j = i
                while j > coilSearchLo {
                    let cont = (shoulderCoil[j-1] < coilThreshold && rot[j-1] <= rot[j])
                    if cont { j -= 1 } else { break }
                }
                coilStart = j
                break
            }
        }
        if let s = coilStart, let e = coilEnd, s < e {
            result.append(makePhase(.coil, s...e))
        }
        
        // 3) ACCELERATION — between coil end and impact, detect first rotation flip to positive
        var accelStart: Int? = nil
        var accelEnd: Int? = nil
        let accelSearchLo = (coilEnd ?? max(0, kImpact - 15)) + 1
        if let idx = rotationFlipsPositive(between: accelSearchLo, kImpact) {
            accelStart = idx
            // end right before impact or when energy slope flattens
            var endIdx = kImpact - 1
            // try to find where Δenergy stops growing
            for i in stride(from: kImpact-1, to: idx, by: -1) {
                let d1 = energy[i] - energy[i-1]
                let d2 = energy[i-1] - energy[max(0, i-2)]
                if d1 <= d2 { endIdx = i; break }
            }
            accelEnd = max(idx, endIdx)
        }
        if let s = accelStart, let e = accelEnd, s <= e {
            result.append(makePhase(.acceleration, s...e))
        }
        
        // 4) IMPACT — single frame at anchor
        result.append(makePhase(.impact, kImpact...kImpact))
        let peakEnergy = energy[kImpact]
        
        // 5) FOLLOW-THROUGH — after impact; wrist offset direction + energy decay
        var followStart: Int? = nil
        var followEnd: Int? = nil
        let wristCond: (Int) -> Bool = { i in
            switch strokeType {
            case .forehand: return wristX[i] > followWristFH
            case .backhand: return wristX[i] < followWristBH
            }
        }
        for i in kImpact..<metrics.count {
            if wristCond(i) {
                followStart = i
                break
            }
        }
        if let fs = followStart {
            var i = fs
            while i < metrics.count-1 {
                // end when energy sufficiently low relative to peak or wrist returns toward mid
                if energy[i] < 0.3 * peakEnergy || abs(wristX[i]) < 0.15 {
                    followEnd = max(fs, i)
                    break
                }
                i += 1
            }
            if followEnd == nil { followEnd = metrics.count-1 }
        }
        if let s = followStart, let e = followEnd, s <= e {
            result.append(makePhase(.followThrough, s...e))
        }
        
        // 6) SPLIT-STEP — after follow-through; wide stance + low hands + low energy
        if let lastEnd = (result.last?.frames.last).map({ frame in
            metrics.firstIndex(where: { $0.frameId == frame.frameId }) ?? kImpact
        }) {
            var splitIdx: Int? = nil
            for i in max(lastEnd, kImpact)..<metrics.count {
                if detectSplitStep(in: metrics[i]) {
                    splitIdx = i
                    break
                }
            }
            if let si = splitIdx {
                // extend until end or until energy rises again
                var end = si
                while end < metrics.count-1, energy[end+1] <= max(lowEnergy, energy[end]) {
                    end += 1
                }
                result.append(makePhase(.splitStep, si...end))
            }
        }
        
        // Ensure final order and uniqueness explicitly (defensive)
        let ordered: [StrokeSubPhase] = [.coil, .acceleration, .impact, .followThrough, .splitStep]
        var smoothed: [PhaseSegment] = []
        var lastTime: CMTime = .zero
        for phase in ordered {
            if let seg = result
                .filter({ $0.phase == phase })
                .sorted(by: { ($0.frames.first?.time ?? .zero) < ($1.frames.first?.time ?? .zero) })
                .first,
               let t = seg.frames.first?.time, t > lastTime {
                smoothed.append(seg)
                lastTime = t
            }
        }
        return smoothed
    }

    // MARK: - Stroke Type Classification (Refined Logic)
    /// Classifies the stroke type for a segment of metrics, using refined rules and persistence/lockout.
    /// - Parameters:
    ///   - metrics: The metrics (frames) in the segment.
    ///   - lastType: The last known stroke type, if any.
    /// - Returns: The classified StrokeType.
    private func classifyStrokeType(
        metrics: [MotionPoint],
        lastType: StrokeType?
    ) -> StrokeType {
        // Use rules:
        // - rightShoulder.x < leftShoulder.x - 0.1 * shoulderSpan and wristXOffsetRel > +0.2 => .forehand
        // - rightShoulder.x > leftShoulder.x + 0.1 * shoulderSpan and wristXOffsetRel < -0.2 => .backhand
        // - If |wristXOffsetRel| <= 0.1, retain lastType.
        // - Require ≥5 consecutive frames for a new type before switching (persistence).
        // - After a switch, lockout for 9 frames before allowing another switch.
        var candidate: StrokeType? = nil
        var candidateCount = 0
        var lockout = 0
        var currentType = lastType ?? .forehand
        for (_, metric) in metrics.enumerated() {
            let wristXOffsetRel = metric.wristXOffsetRel
            let shoulderSpan = metric.shoulderSpan

            // skip if values are near zero (no meaningful motion)
            if abs(wristXOffsetRel) < 0.05 || shoulderSpan < 0.05 {
                continue
            }
            // Ambiguous: |wristXOffsetRel| <= 0.1
            if abs(wristXOffsetRel) <= 0.1 {
                // retain previous
                continue
            }
            // Only consider switching if not in lockout
            if lockout > 0 {
                lockout -= 1
                continue
            }
            // Rule for forehand
            if wristXOffsetRel > 0.2 {
                if candidate == .forehand {
                    candidateCount += 1
                } else {
                    candidate = .forehand
                    candidateCount = 1
                }
                // Confirm switch
                if candidateCount >= 5 && currentType != .forehand {
                    currentType = .forehand
                    lockout = 9
                }
            }
            // Rule for backhand
            else if wristXOffsetRel < -0.2 {
                if candidate == .backhand {
                    candidateCount += 1
                } else {
                    candidate = .backhand
                    candidateCount = 1
                }
                if candidateCount >= 5 && currentType != .backhand {
                    currentType = .backhand
                    lockout = 9
                }
            }
            // If neither, ambiguous, retain last type
            else {
                // retain
                continue
            }
        }
        return currentType
    }

    // MARK: - Phase Confidence Helper
    private func computeConfidence(from values: [CGFloat]) -> Double {
        guard values.count > 1 else { return 1.0 }
        let mean = values.reduce(0, +) / CGFloat(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / CGFloat(values.count - 1)
        let normalized = min(Double(variance / 0.1), 1.0)
        return max(0.0, 1.0 - normalized)
    }
    
    // MARK: - Stroke-Level Confidence Helper
    private func computeStrokeConfidence(
        from sortedMetrics: [MotionPoint],
        phaseSegments: [PhaseSegment],
        baselineEnergy: CGFloat
    ) -> Double {
        let phaseConf = phaseSegments.map(\.confidence)
        let avgPhase = phaseConf.isEmpty ? 0.8 : phaseConf.reduce(0,+)/Double(phaseConf.count)
        let energyValues = sortedMetrics.map { $0.energyRearHybrid }
        let energyConf = computeConfidence(from: energyValues)
        let maxEnergy = energyValues.max() ?? 0
        let energyRatio = Double(maxEnergy / (baselineEnergy + 1e-3))
        let normalizedRatio = min(1.0, energyRatio / 3.0)  // Cap at 3× baseline
        return (avgPhase * 0.5) + (energyConf * 0.3) + (normalizedRatio * 0.2)
    }

}

