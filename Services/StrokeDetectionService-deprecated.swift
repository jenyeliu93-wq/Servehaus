////
////  StrokeDetectionService.swift
////
////  Purpose:
////  Implements the pre-phase of stroke detection for biomechanical analysis.
////  Responsibilities:
////    - Computes biomechanical metrics from sequences of FramePoseResult frames.
////    - Outputs a motion series of MotionPoint objects containing computed features.
////    - Does not yet perform segmentation or stroke phase detection.
////
////  Outputs:
////    - [MotionPoint]: A series of motion points with energy, separation, wrist offset, and shoulder rotation sign.
////
//import Foundation
//internal import CoreMedia
//import Vision
//import CoreGraphics
//import AVFoundation
//// MARK: - MotionPoint
//public enum StrokeType: String {
//    case forehand = "forehand"
//    case backhand = "backhand"
//}
//
//// MARK: - Phase 2: Stroke Classification
//// Weighted-Window Classifier
//// Uses biomechanical signals in a short window around the impact (energy peak) frame.
//// Robust against lag between hip/shoulder rotation and wrist extension.
//
//internal func classifyStrokeType(for segment: StrokeSegment) -> StrokeType {
//    guard !segment.frames.isEmpty else { return .forehand }
//
//    // 1️⃣ Find energy peak index
//    guard let peakIndex = segment.frames.indices.max(by: { segment.frames[$0].energy < segment.frames[$1].energy }) else {
//        return .forehand
//    }
//
//    // 2️⃣ Define ±2 frame window around peak
//    let window = max(0, peakIndex - 2)...min(segment.frames.count - 1, peakIndex + 2)
//    let windowFrames = Array(segment.frames[window])
//
//    // 3️⃣ Compute average biomechanical features in window
//    let meanRot = windowFrames.map(\.rotSign).reduce(0, +) / CGFloat(windowFrames.count)
//    let meanWrist = windowFrames.map(\.wristOffset).reduce(0, +) / CGFloat(windowFrames.count)
//    let meanSep = windowFrames.map(\.sep).reduce(0, +) / CGFloat(windowFrames.count)
//
//    // 4️⃣ Classification logic
//    if meanWrist > 0.01 && meanRot > 0 {
//        return .forehand
//    } else if meanWrist < -0.01 && meanRot < 0 {
//        return .backhand
//    } else {
//        // fallback using torso separation
//        return meanSep >= 0 ? .forehand : .backhand
//    }
//}
//
///*
// // MARK: - Future Iteration (v0.6+)
// // Logistic regression or time-series model approach could replace the above rule:
// // featureVector = [avgRot, peakRot, avgWrist, peakWrist, sepAtPeak, preEnergySlope, postEnergySlope]
// // score = w0 + w1*peakWrist + w2*rotSign + w3*sep + w4*preEnergySlope
// // return score > 0 ? .forehand : .backhand
// */
//
//
//// MARK: - StrokeSegment
//
///// Represents a segmented stroke phase with type, time range, and associated motion points.
///// The `motionPoints` property is used for consistency with feature extraction and downstream processing.
//public struct StrokeSegment {
//    public let id: UUID                      // each individual stroke
//    public let type: StrokeType              // forehand / backhand
//    public let timeRange: ClosedRange<CMTime>
//    public let frames: [MotionPoint]         // per-frame biomechanical data
//    public let avgEnergy: Double
//    public let avgRotation: Double
//}
//
//// MARK: - Required Types
//// This file depends on the project's existing definitions of FramePoseResult and JointName elsewhere.
//public struct MotionPoint {
//    public let time: CMTime
//    public let energy: CGFloat
//    public let sep: CGFloat
//    public let wristOffset: CGFloat
//    public let rotSign: CGFloat
//    public let frameId: UUID
//}
//
//
//// MARK: - StrokeDetectionService
//
///// Provides stroke detection and biomechanical feature extraction.
//public enum StrokeDetectionService {
//
//    /// Computes biomechanical metrics from consecutive FramePoseResult frames.
//    /// - Parameter frames: Array of FramePoseResult objects in temporal order.
//    /// - Returns: Array of MotionPoint containing computed features.
//    internal static func detectStrokes(from frames: [FramePoseResult]) async -> [MotionPoint] {
//        return computeMotionPoints(from: frames)
//    }
//
//    internal static func computeMotionPoints(from frames: [FramePoseResult]) -> [MotionPoint] {
//        guard frames.count >= 2 else { return [] }
//        var motionSeries: [MotionPoint] = []
//
//        // Assume frame interval (time between frames) is 0.05 seconds for velocity calculations
//        let frameInterval: CGFloat = 0.05
//
//        // Iterate over frame pairs (previous, current)
//        for i in 1..<frames.count {
//            let prev = frames[i - 1]
//            let curr = frames[i]
//
//            // -- Biomechanical metrics computation --
//
//            // 1. Compute wrist movement (Euclidean distance between wrists, both sides)
//            let prevLW = prev.joints[.leftWrist] ?? .zero
//            let prevRW = prev.joints[.rightWrist] ?? .zero
//            let currLW = curr.joints[.leftWrist] ?? .zero
//            let currRW = curr.joints[.rightWrist] ?? .zero
//            let wristMove = hypot(currRW.x - prevRW.x, currRW.y - prevRW.y) +
//                            hypot(currLW.x - prevLW.x, currLW.y - prevLW.y)
//
//            // 2. Compute shoulder movement (Euclidean distance, both sides)
//            let prevLS = prev.joints[.leftShoulder] ?? .zero
//            let prevRS = prev.joints[.rightShoulder] ?? .zero
//            let currLS = curr.joints[.leftShoulder] ?? .zero
//            let currRS = curr.joints[.rightShoulder] ?? .zero
//            let shoulderMove = hypot(currRS.x - prevRS.x, currRS.y - prevRS.y) +
//                               hypot(currLS.x - prevLS.x, currLS.y - prevLS.y)
//
//            // 3. Compute hip angular velocity (absolute difference in hip line angle between frames)
//            let prevLH = prev.joints[.leftHip] ?? .zero
//            let prevRH = prev.joints[.rightHip] ?? .zero
//            let currLH = curr.joints[.leftHip] ?? .zero
//            let currRH = curr.joints[.rightHip] ?? .zero
//
//            let prevHipAngle = atan2(prevRH.y - prevLH.y, prevRH.x - prevLH.x)
//            let currHipAngle = atan2(currRH.y - currLH.y, currRH.x - currLH.x)
//            var hipAngularDiff = currHipAngle - prevHipAngle
//            // Normalize to [-π, π]
//            while hipAngularDiff > .pi { hipAngularDiff -= 2 * .pi }
//            while hipAngularDiff < -.pi { hipAngularDiff += 2 * .pi }
//
//            let hipAngularSpeed = abs(hipAngularDiff) / frameInterval
//
//            // 4. Compute speeds for wrist and shoulder movements
//            let wristSpeed = wristMove / frameInterval
//            let shoulderSpeed = shoulderMove / frameInterval
//
//            // 5. Compute weighted energy using velocity squared model (v2)
//            //    This version aligns more closely with biomechanics by considering velocity (not displacement),
//            //    introduces hip torque (angular velocity), and reduces wrist weighting.
//            let energy = 0.5 * (0.5 * pow(shoulderSpeed, 2) + 0.3 * pow(wristSpeed, 2) + 0.2 * pow(hipAngularSpeed, 2))
//
//            // 6. Compute hip–shoulder separation angle (sep)
//            //    Measures torso rotation: angle between shoulder line and hip line, in degrees.
//            let currHipVec = vectorBetween(curr.joints[.leftHip], curr.joints[.rightHip])
//            let currShoulderVec = vectorBetween(curr.joints[.leftShoulder], curr.joints[.rightShoulder])
//            let sep = angleBetweenVectors(currShoulderVec, currHipVec) * 180 / .pi // degrees
//
//            // 7. Compute wrist x-offset relative to root center (wristOffset)
//            //    Measures lateral deviation of wrist from body center.
//            let currRoot = curr.joints[.root] ?? .zero
//            let wristOffset = (currRW.x - currRoot.x)
//
//            // 8. Compute shoulder rotation sign (rotSign)
//            //    Measures angular velocity of shoulder line between frames, normalized to [-π, π].
//            let prevShoulderAngle = atan2(prevRS.y - prevLS.y, prevRS.x - prevLS.x)
//            let currShoulderAngle = atan2(currRS.y - currLS.y, currRS.x - currLS.x)
//            var deltaAngle = currShoulderAngle - prevShoulderAngle
//            // Normalize to [-π, π]
//            while deltaAngle > .pi { deltaAngle -= 2 * .pi }
//            while deltaAngle < -.pi { deltaAngle += 2 * .pi }
//            let rotSign = deltaAngle
//
//            // 9. Use the current frame's time
//            let time = curr.time
//
//            // 10. Collect into MotionPoint
//            let point = MotionPoint(
//                time: time,
//                energy: CGFloat(energy),
//                sep: CGFloat(sep),
//                wristOffset: CGFloat(wristOffset),
//                rotSign: CGFloat(rotSign),
//                frameId: curr.id   // ✅ use frame’s existing ID for traceability
//            )
//            motionSeries.append(point)
//        }
//        return motionSeries
//    }
//
//    // MARK: - Phase 1: Stroke Segmentation
//
//    /// Segments strokes from a series of MotionPoints based on energy patterns.
//    /// Uses adaptive thresholds to distinguish between professional (clear peaks) and amateur (flatter) players.
//    ///
//    /// - Parameter motionPoints: Array of MotionPoint in temporal order.
//    /// - Returns: Array of StrokeSegment representing segmented stroke phases.
//internal static func segmentStrokes(from motionPoints: [MotionPoint]) -> [StrokeSegment] {
//    guard motionPoints.count > 2 else { return [] }
//
//    // Extract energy values for adaptive thresholding
//    let energies = motionPoints.map { $0.energy }
//    let maxEnergy = energies.max() ?? 0
//    let minEnergy = energies.min() ?? 0
//    let energyRange = maxEnergy - minEnergy
//
//    // Adaptive thresholds to support both pro (clear peaks) and amateur (flatter) players
//    let lowThreshold = minEnergy + 0.15 * energyRange
//    let highThreshold = minEnergy + 0.5 * energyRange
//
//    // Identify local minima and maxima indices
//    var localMinIndices: [Int] = []
//    var localMaxIndices: [Int] = []
//
//    for i in 1..<(energies.count - 1) {
//        let prev = energies[i - 1], curr = energies[i], next = energies[i + 1]
//        if curr < prev && curr < next && curr < lowThreshold {
//            localMinIndices.append(i)
//        } else if curr > prev && curr > next && curr > highThreshold {
//            localMaxIndices.append(i)
//        }
//    }
//
//    // Ensure boundary minima for segmentation start/end
//    if localMinIndices.isEmpty || localMinIndices.first! > 0 {
//        localMinIndices.insert(0, at: 0)
//    }
//    if localMinIndices.last! < energies.count - 1 {
//        localMinIndices.append(energies.count - 1)
//    }
//
//    var segments: [StrokeSegment] = []
//
//    // Group frames between consecutive minima to form stroke segments
//    for idx in 0..<(localMinIndices.count - 1) {
//        let start = localMinIndices[idx]
//        let end = localMinIndices[idx + 1]
//
//        // Ensure there's at least one valid energy peak between boundaries
//        guard let peakIndex = localMaxIndices.first(where: { $0 > start && $0 < end }) else { continue }
//
//        // Extract frames belonging to this segment
//        let segmentFrames = Array(motionPoints[start...end])
//        let peakFrame = motionPoints[peakIndex]
//
//        // Determine stroke type heuristically based on wrist offset direction
//        let strokeType: StrokeType = peakFrame.wristOffset >= 0 ? .forehand : .backhand
//
//        // --- Compute summary metrics ---
//        let avgEnergy = segmentFrames.map(\.energy).reduce(0, +) / Double(segmentFrames.count)
//        let avgRotation = segmentFrames.map(\.rotSign).reduce(0, +) / Double(segmentFrames.count)
//
//        // --- Construct final StrokeSegment with unique ID and traceable metadata ---
//        let segment = StrokeSegment(
//            id: UUID(),  // unique stroke identifier
//            type: strokeType,
//            timeRange: segmentFrames.first!.time...segmentFrames.last!.time,
//            frames: segmentFrames,
//            avgEnergy: avgEnergy,
//            avgRotation: avgRotation
//        )
//
//        segments.append(segment)
//    }
//
//    return segments
//}
//}
//
//// MARK: - Utility functions
//
//private func vectorBetween(_ a: CGPoint?, _ b: CGPoint?) -> CGVector {
//    guard let a = a, let b = b else { return .zero }
//    return CGVector(dx: b.x - a.x, dy: b.y - a.y)
//}
//
//private func angleBetweenVectors(_ v1: CGVector, _ v2: CGVector) -> CGFloat {
//    let dot = v1.dx * v2.dx + v1.dy * v2.dy
//    let mag1 = hypot(v1.dx, v1.dy)
//    let mag2 = hypot(v2.dx, v2.dy)
//    guard mag1 > 0, mag2 > 0 else { return 0 }
//    let cosTheta = max(-1.0, min(1.0, dot / (mag1 * mag2)))
//    return acos(cosTheta)
//}
//
//let prePadding: Double = 0.15   // seconds before stroke start
//let postPadding: Double = 0.25  // seconds after stroke end
