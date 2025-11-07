import Foundation
import Vision
import CoreMedia
import CoreGraphics

/// MARK: - Biomechanics Consolidation
/// Consolidates all core biomechanics metrics as static functions for centralized access.
public struct Biomechanics {
    /// Compute the Euclidean distance between left and right shoulders.
    static func shoulderSpan(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        PoseAnalysisService.shoulderSpan(joints)
    }
    /// Compute the Euclidean distance between left and right hips.
    static func hipSpan(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        PoseAnalysisService.hipSpan(joints)
    }
    /// Compute the Euclidean distance between left and right ankles.
    static func footSpan(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        PoseAnalysisService.footSpan(joints)
    }
    /// Compute wrist height relative to shoulder midpoint normalized by shoulder span.
    static func wristHeightRel(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        PoseAnalysisService.wristHeightRel(joints)
    }
    /// Compute wrist horizontal offset relative to root joint normalized by shoulder span.
    static func wristXOffsetRel(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        PoseAnalysisService.wristXOffsetRel(joints)
    }
    /// Compute the angular speed of the forearm between two frames.
    static func forearmAngularSpeed(prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                    next: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                    dt: Double) -> Double? {
        PoseAnalysisService.forearmAngularSpeed(prev: prev, next: next, dt: dt)
    }
    /// Compute wrist linear speed between two frames.
    static func wristLinearSpeed(prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                 next: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                 dt: Double) -> Double? {
        guard dt > 0,
              let prevWrist = PoseAnalysisService.joint(.rightWrist, prev) ?? PoseAnalysisService.joint(.leftWrist, prev),
              let nextWrist = PoseAnalysisService.joint(.rightWrist, next) ?? PoseAnalysisService.joint(.leftWrist, next)
        else { return nil }
        let wristDist = hypot(Double(nextWrist.x - prevWrist.x), Double(nextWrist.y - prevWrist.y))
        return wristDist / dt
    }
    /// Compute center of mass (hip midpoint) speed between two frames.
    static func comSpeed(prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                         next: [VNHumanBodyPoseObservation.JointName: CGPoint],
                         dt: Double) -> Double? {
        guard dt > 0,
              let prevLH = PoseAnalysisService.joint(.leftHip, prev), let prevRH = PoseAnalysisService.joint(.rightHip, prev),
              let nextLH = PoseAnalysisService.joint(.leftHip, next), let nextRH = PoseAnalysisService.joint(.rightHip, next)
        else { return nil }
        let prevCOM = CGPoint(x: (prevLH.x + prevRH.x) / 2.0, y: (prevLH.y + prevRH.y) / 2.0)
        let nextCOM = CGPoint(x: (nextLH.x + nextRH.x) / 2.0, y: (nextLH.y + nextRH.y) / 2.0)
        let comDist = hypot(Double(nextCOM.x - prevCOM.x), Double(nextCOM.y - prevCOM.y))
        return comDist / dt
    }
    /// Compute hand speed ratio (leftHandSpeed / rightHandSpeed) between two frames.
    static func handSpeedRatio(prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                               next: [VNHumanBodyPoseObservation.JointName: CGPoint],
                               dt: Double) -> Double? {
        guard dt > 0 else { return nil }
        var leftHandSpeed: Double? = nil
        var rightHandSpeed: Double? = nil
        if let prevLeftWrist = PoseAnalysisService.joint(.leftWrist, prev), let nextLeftWrist = PoseAnalysisService.joint(.leftWrist, next) {
            let dist = hypot(Double(nextLeftWrist.x - prevLeftWrist.x), Double(nextLeftWrist.y - prevLeftWrist.y))
            leftHandSpeed = dist / dt
        }
        if let prevRightWrist = PoseAnalysisService.joint(.rightWrist, prev), let nextRightWrist = PoseAnalysisService.joint(.rightWrist, next) {
            let dist = hypot(Double(nextRightWrist.x - prevRightWrist.x), Double(nextRightWrist.y - prevRightWrist.y))
            rightHandSpeed = dist / dt
        }
        if let lhs = leftHandSpeed, let rhs = rightHandSpeed, rhs != 0 {
            return lhs / rhs
        }
        return nil
    }
    /// Compute the hybrid energy metric (energyRearHybrid).
    static func energyRearHybrid(prevPrev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                 prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                 next: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                 dt: Double) -> (energy: Double, footSpan: Double?, wristLinearSpeed: Double?, handSpeedRatio: Double?, comSpeed: Double?)? {
        PoseAnalysisService.energyRearHybrid(prevPrev: prevPrev, prev: prev, next: next, dt: dt)
    }
}


/// A utility service providing stateless biomechanics calculations for human pose analysis.
/// This service computes per-frame biomechanics metrics used to generate `[MotionPoint]` for the `MotionFeaturePipeline`.
/// It does NOT handle pose detection or phase detection, which belong to other services.
public final class PoseAnalysisService { }

// MARK: - Geometry & Angle Calculations
extension PoseAnalysisService {

    /// Retrieve a joint point from the dictionary, returns nil if missing.
    /// - Parameters:
    ///   - name: The joint name to retrieve.
    ///   - dict: Dictionary mapping joint names to CGPoint.
    /// - Returns: CGPoint of the joint or nil if not present.
    static func joint(_ name: VNHumanBodyPoseObservation.JointName,
                      _ dict: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> CGPoint? {
        dict[name]
    }
    

    /// Calculate minimal angle difference wrapped to [-π, π].
    /// - Parameters:
    ///   - a1: First angle in radians.
    ///   - a0: Second angle in radians.
    /// - Returns: Minimal difference between angles.
    private static func angleDelta(_ a1: Double, _ a0: Double) -> Double {
        var d = a1 - a0
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}

// MARK: - Rear View Metrics
extension PoseAnalysisService {
    
    /// Compute the Euclidean distance between left and right shoulders.
    /// - Parameter joints: Dictionary of joint points.
    /// - Returns: Shoulder span distance or nil if joints missing.
    static func shoulderSpan(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        guard let ls = joint(.leftShoulder, joints), let rs = joint(.rightShoulder, joints) else { return nil }
        return Double(hypot(rs.x - ls.x, rs.y - ls.y))
    }
    
    /// Compute the Euclidean distance between left and right hips.
    /// - Parameter joints: Dictionary of joint points.
    /// - Returns: Hip span distance or nil if joints missing.
    static func hipSpan(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        guard let lh = joint(.leftHip, joints), let rh = joint(.rightHip, joints) else { return nil }
        return Double(hypot(rh.x - lh.x, rh.y - lh.y))
    }
    
    /// Compute the Euclidean distance between left and right ankles.
    /// - Parameter joints: Dictionary of joint points.
    /// - Returns: Foot span distance or nil if joints missing.
    static func footSpan(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        guard let la = joint(.leftAnkle, joints), let ra = joint(.rightAnkle, joints) else { return nil }
        return Double(hypot(ra.x - la.x, ra.y - la.y))
    }
    
    /// Compute shoulder coil factor as relative change in shoulder span between two frames.
    /// Formula: (shoulderSpan_next - shoulderSpan_prev) / shoulderSpan_prev
    /// - Parameters:
    ///   - prev: Previous joint points.
    ///   - next: Next joint points.
    /// - Returns: Shoulder coil factor or nil if spans unavailable or zero.
    static func shoulderCoilFactor(prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                   next: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        guard let prevSpan = shoulderSpan(prev), prevSpan > 0,
              let nextSpan = shoulderSpan(next) else { return nil }
        return (nextSpan - prevSpan) / prevSpan
    }
    
    /// Compute hip coil factor as relative change in hip span between two frames.
    /// Formula: (hipSpan_next - hipSpan_prev) / hipSpan_prev
    /// - Parameters:
    ///   - prev: Previous joint points.
    ///   - next: Next joint points.
    /// - Returns: Hip coil factor or nil if spans unavailable or zero.
    static func hipCoilFactor(prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                              next: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        guard let prevSpan = hipSpan(prev), prevSpan > 0,
              let nextSpan = hipSpan(next) else { return nil }
        return (nextSpan - prevSpan) / prevSpan
    }
    
    /// Compute wrist height relative to shoulder midpoint normalized by shoulder span.
    /// Formula: (wristY - shoulderMidY) / shoulderSpan
    /// Uses right wrist if available; else left wrist.
    /// - Parameter joints: Dictionary of joint points.
    /// - Returns: Relative wrist height or nil if joints missing.
    static func wristHeightRel(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        guard let shoulderSpan = shoulderSpan(joints), shoulderSpan > 0,
              let rs = joint(.rightShoulder, joints),
              let ls = joint(.leftShoulder, joints) else { return nil }
        let shoulderMidY = (rs.y + ls.y) / 2.0
        guard let wrist = joint(.rightWrist, joints) ?? joint(.leftWrist, joints) else { return nil }
        return Double(wrist.y - shoulderMidY) / shoulderSpan
    }
    
    /// Compute wrist horizontal offset relative to root joint normalized by shoulder span.
    /// Formula: (wristX - rootX) / shoulderSpan
    /// - Parameter joints: Dictionary of joint points.
    /// - Returns: Relative wrist horizontal offset or nil if joints missing.
    static func wristXOffsetRel(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        guard let shoulderSpan = shoulderSpan(joints), shoulderSpan > 0,
              let root = joint(.root, joints),
              let wrist = joint(.rightWrist, joints) ?? joint(.leftWrist, joints) else { return nil }
        return Double(wrist.x - root.x) / shoulderSpan
    }
    
    /// Compute the angular speed of the forearm between two frames.
    /// Angle is between vectors (shoulder -> elbow) and (elbow -> wrist).
    /// Angular speed = Δangle / Δt normalized by π.
    /// - Parameters:
    ///   - prev: Previous joint points.
    ///   - next: Next joint points.
    ///   - dt: Time difference in seconds.
    /// - Returns: Angular speed normalized by π or nil if joints missing or dt <= 0.
    static func forearmAngularSpeed(prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                   next: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                   dt: Double) -> Double? {
        guard dt > 0,
              let prevAngle = forearmAngle(joints: prev),
              let nextAngle = forearmAngle(joints: next) else { return nil }
        let dAngle = abs(angleDelta(nextAngle, prevAngle))
        return dAngle / (dt * .pi)
    }
    
    /// Helper to compute the angle between (shoulder -> elbow) and (elbow -> wrist) vectors.
    /// Returns angle in radians or nil if joints missing.
    private static func forearmAngle(joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        guard let shoulder = joint(.rightShoulder, joints) ?? joint(.leftShoulder, joints),
              let elbow = joint(.rightElbow, joints) ?? joint(.leftElbow, joints),
              let wrist = joint(.rightWrist, joints) ?? joint(.leftWrist, joints) else { return nil }
        let vec1 = vector(from: shoulder, to: elbow)
        let vec2 = vector(from: elbow, to: wrist)
        return angleBetweenVectors(vec1, vec2)
    }
    
    /// Compute a vector from point a to b.
    private static func vector(from a: CGPoint, to b: CGPoint) -> (x: Double, y: Double) {
        (Double(b.x - a.x), Double(b.y - a.y))
    }
    
    /// Compute angle between two vectors in radians.
    private static func angleBetweenVectors(_ v1: (x: Double, y: Double), _ v2: (x: Double, y: Double)) -> Double {
        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
        guard mag1 > 0, mag2 > 0 else { return 0 }
        let cosAngle = min(max(dot / (mag1 * mag2), -1), 1)
        return acos(cosAngle)
    }
    
    /// Compute a hybrid energy metric combining wrist linear speed, forearm angular speed,
    /// shoulder and hip coil factor changes, and center of mass speed.
    /// Formula:
    /// energy = 0.5 * [0.25 * wristLinearSpeed² + 0.25 * forearmAngularSpeed² + 0.25 * (ΔshoulderCoilFactor)² + 0.20 * (ΔhipCoilFactor)² + 0.05 * COMspeed²]
    /// where COMspeed is distance between hips midpoints over dt.
    /// Additionally computes footSpan, wristLinearSpeed, and handSpeedRatio as secondary biomechanical indicators supporting subphase detection (e.g., Split Step and Backhand Acceleration).
    /// - Parameters:
    ///   - prev: Previous joint points.
    ///   - next: Next joint points.
    ///   - dt: Time difference in seconds.
    /// - Returns: Tuple containing computed energy and optional footSpan, wristLinearSpeed, handSpeedRatio; or nil if required data missing or dt <= 0.
    static func energyRearHybrid(prevPrev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                 prev: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                 next: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                 dt: Double) -> (energy: Double, footSpan: Double?, wristLinearSpeed: Double?, handSpeedRatio: Double?, comSpeed: Double?)? {
        guard dt > 0 else { return nil }

        // Use Biomechanics static methods to get metrics
        guard let wristLinearSpeed = Biomechanics.wristLinearSpeed(prev: prev, next: next, dt: dt) else { return nil }
        guard let forearmAngSpeed = Biomechanics.forearmAngularSpeed(prev: prev, next: next, dt: dt) else { return nil }
        guard let prevShoulderCoil = shoulderCoilFactor(prev: prevPrev, next: prev),
              let nextShoulderCoil = shoulderCoilFactor(prev: prev, next: next) else { return nil }
        let deltaShoulderCoil = nextShoulderCoil - prevShoulderCoil
        guard let prevHipCoil = hipCoilFactor(prev: prev, next: prev),
              let nextHipCoil = hipCoilFactor(prev: next, next: next) else { return nil }
        let deltaHipCoil = nextHipCoil - prevHipCoil
        guard let comSpeed = Biomechanics.comSpeed(prev: prev, next: next, dt: dt) else { return nil }
        let energy = 0.5 * (
            0.25 * wristLinearSpeed * wristLinearSpeed +
            0.25 * forearmAngSpeed * forearmAngSpeed +
            0.25 * deltaShoulderCoil * deltaShoulderCoil +
            0.20 * deltaHipCoil * deltaHipCoil +
            0.05 * comSpeed * comSpeed
        )
        let footSpan = Biomechanics.footSpan(next)
        let handSpeedRatio = Biomechanics.handSpeedRatio(prev: prev, next: next, dt: dt)
        return (energy, footSpan, wristLinearSpeed, handSpeedRatio, comSpeed)
    }
}

// MARK: - MotionPoint Calculation
extension PoseAnalysisService {
    /// Computes the six core MotionPoint metrics from two frames.
    /// - Parameters:
    ///   - prev: The previous FramePoseResult.
    ///   - next: The next FramePoseResult.
    /// - Returns: A MotionPoint or nil if required data is missing.
    ///
    /// Note on `rotSign`:
    /// The `rotSign` (shoulder coil sign) is a simple indicator (-1, 0, +1) of the direction of shoulder coil movement.
    /// Unlike other metrics (which are continuous and carry detailed biomechanical information), `rotSign` is intentionally
    /// kept simple to provide a quick, discrete marker for rotation directionality. This is sufficient for most downstream
    /// logic that only needs to know the direction rather than the magnitude or nuance of the coil.
    static func computeMotionPoint(prev: FramePoseResult, next: FramePoseResult) -> MotionPoint? {
        let dt = Double(next.time.seconds - prev.time.seconds)
        guard dt > 0 else { return nil }
        // Shoulder coil factor
        guard let shoulderCoil = shoulderCoilFactor(prev: prev.joints, next: next.joints) else { return nil }
        // Hip coil factor
        guard let hipCoil = hipCoilFactor(prev: prev.joints, next: next.joints) else { return nil }
        // Wrist height relative to shoulder midpoint
        guard let wristHeight = wristHeightRel(next.joints) else { return nil }
        // Wrist horizontal offset relative to root
        guard let wristXOffset = wristXOffsetRel(next.joints) else { return nil }
        // Shoulder coil sign
        let rotSign = shoulderCoil.sign
        // Energy hybrid metric and additional secondary biomechanical indicators
        guard let energyResults = energyRearHybrid(prevPrev: prev.joints, prev: prev.joints, next: next.joints, dt: dt) else { return nil }

        let footSpanVal = energyResults.footSpan ?? 0.0
        let forearmAngSpeedVal = forearmAngularSpeed(prev: prev.joints, next: next.joints, dt: dt) ?? 0.0
        let wristLinearSpeedVal = energyResults.wristLinearSpeed ?? 0.0
        let comSpeedVal = energyResults.comSpeed ?? 0.0
        let handSpeedRatioVal = energyResults.handSpeedRatio ?? 0.0

        // Debug print of computed metric values (only in debug mode)
//        #if DEBUG
//        print("Metrics: footSpan=\(footSpanVal), forearmAngularSpeed=\(forearmAngSpeedVal), wristLinearSpeed=\(wristLinearSpeedVal), comSpeed=\(comSpeedVal), handSpeedRatio=\(handSpeedRatioVal)")
//        #endif

        let point: MotionPoint = MotionPoint(
            time: next.time,
            frameId: next.id,
            energyRearHybrid: CGFloat(energyResults.energy),
            shoulderCoilFactor: CGFloat(shoulderCoil),
            hipCoilFactor: CGFloat(hipCoil),
            rotSign: CGFloat(rotSign == .plus ? 1.0 : (rotSign == .minus ? -1.0 : 0.0)),
            shoulderSpan: CGFloat(shoulderSpan(next.joints) ?? 0.0),
            hipSpan: CGFloat(hipSpan(next.joints) ?? 0.0),
            wristXOffsetRel: CGFloat(wristXOffset),
            wristHeightRel: CGFloat(wristHeight),
            footSpan: CGFloat(footSpanVal),
            forearmAngularSpeed: CGFloat(forearmAngSpeedVal),
            wristLinearSpeed: CGFloat(wristLinearSpeedVal),
            comSpeed: CGFloat(comSpeedVal),
            handSpeedRatio: CGFloat(handSpeedRatioVal)
        )
        return point
    }
}

// No confidence scoring: obsolete for MotionPoint pipeline.

// MARK: - Vision Integration
extension PoseAnalysisService {

    /// Detects human body poses in a given CGImage using Vision.
    ///
    /// This method runs a `VNDetectHumanBodyPoseRequest` on the provided image and returns
    /// all detected `VNHumanBodyPoseObservation` objects. It is intended as a helper for
    /// extracting pose information from raw video or camera frames as part of the pose analysis pipeline.
    ///
    /// - Parameter cgImage: The input image for pose detection.
    /// - Returns: An array of `VNHumanBodyPoseObservation` representing detected human poses.
    /// - Throws: An error if Vision fails to process the image.
    static func detectPoses(in cgImage: CGImage) async throws -> [VNHumanBodyPoseObservation] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
//        let results = request.results as? [VNHumanBodyPoseObservation] ?? []
        let results = request.results ?? []
        return results
    }
    

    /// Extracts joint points from a Vision human body pose observation, filtering by confidence.
    ///
    /// This method retrieves all available joint locations from the provided observation
    /// and returns a dictionary mapping joint names to their image coordinates. Only joints
    /// with a confidence above 0.1 are included to reduce noise. This is a key step for converting
    /// Vision's output into a format suitable for geometric and kinematic analysis.
    ///
    /// - Parameter observation: The Vision human body pose observation.
    /// - Returns: A dictionary mapping joint names to their corresponding `CGPoint` locations.
    static func jointPoints(from observation: VNHumanBodyPoseObservation) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return [:] }
        var result: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in recognizedPoints {
            if point.confidence > 0.1 {
                result[joint] = CGPoint(x: point.x, y: point.y)
            }
        }
        return result
    }
}

