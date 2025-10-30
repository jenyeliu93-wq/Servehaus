// SharedTypes.swift (new, keeps access control tidy)
import Foundation
import CoreMedia
import Vision
import CoreGraphics

public enum StrokeType { case forehand, backhand }

public enum StrokeSubPhase: String, CaseIterable {
    case coil, acceleration, impact, followThrough, splitStep
}

public struct FrameTimeMeta: Codable {
    public let frameIndex: Int
    public let timestampSec: Double
    public let frameInterval: Double
    public let isInterpolated: Bool
    public init(frameIndex: Int, timestampSec: Double, frameInterval: Double, isInterpolated: Bool) {
        self.frameIndex = frameIndex
        self.timestampSec = timestampSec
        self.frameInterval = frameInterval
        self.isInterpolated = isInterpolated
    }
}

public struct FramePoseResult: Identifiable {
    public let id: UUID
    public let videoId: UUID
    public let time: CMTime
    public let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    public let confidences: [VNHumanBodyPoseObservation.JointName: Double]
    public let timeMeta: FrameTimeMeta?
    public init(id: UUID = UUID(),
                videoId: UUID,
                time: CMTime,
                joints: [VNHumanBodyPoseObservation.JointName: CGPoint],
                confidences: [VNHumanBodyPoseObservation.JointName: Double],
                timeMeta: FrameTimeMeta?) {
        self.id = id
        self.videoId = videoId
        self.time = time
        self.joints = joints
        self.confidences = confidences
        self.timeMeta = timeMeta
    }
}

public struct MotionPoint {
    public let time: CMTime
    public let frameId: UUID
    public let energyRearHybrid: CGFloat
    public let shoulderCoilFactor: CGFloat
    public let hipCoilFactor: CGFloat
    public let rotSign: CGFloat
    public let shoulderSpan: CGFloat
    public let hipSpan: CGFloat
    public let wristXOffsetRel: CGFloat
    public let wristHeightRel: CGFloat
    public let sepDeg: CGFloat
    public init(time: CMTime, frameId: UUID, energyRearHybrid: CGFloat,
                shoulderCoilFactor: CGFloat, hipCoilFactor: CGFloat, rotSign: CGFloat,
                shoulderSpan: CGFloat, hipSpan: CGFloat,
                wristXOffsetRel: CGFloat, wristHeightRel: CGFloat, sepDeg: CGFloat) {
        self.time = time
        self.frameId = frameId
        self.energyRearHybrid = energyRearHybrid
        self.shoulderCoilFactor = shoulderCoilFactor
        self.hipCoilFactor = hipCoilFactor
        self.rotSign = rotSign
        self.shoulderSpan = shoulderSpan
        self.hipSpan = hipSpan
        self.wristXOffsetRel = wristXOffsetRel
        self.wristHeightRel = wristHeightRel
        self.sepDeg = sepDeg
    }
}

public struct PhaseSegment {
    public let phase: StrokeSubPhase
    public let confidence: Double
    public let frames: [MotionPoint]
    public let metrics: [String: Double]
    public let score: Double
    public let formula: String
    public init(phase: StrokeSubPhase, confidence: Double, frames: [MotionPoint],
                metrics: [String: Double], score: Double, formula: String) {
        self.phase = phase
        self.confidence = confidence
        self.frames = frames
        self.metrics = metrics
        self.score = score
        self.formula = formula
    }
}

public struct StrokeSegment {
    public let id: UUID
    public var type: StrokeType
    public let timeRange: ClosedRange<CMTime>
    public let frames: [MotionPoint]
    public let phases: [PhaseSegment]
    public let aggregates: [String: Double]
    public let confidence: Double
    public init(id: UUID = UUID(), type: StrokeType, timeRange: ClosedRange<CMTime>,
                frames: [MotionPoint], phases: [PhaseSegment],
                aggregates: [String: Double], confidence: Double) {
        self.id = id
        self.type = type
        self.timeRange = timeRange
        self.frames = frames
        self.phases = phases
        self.aggregates = aggregates
        self.confidence = confidence
    }
}

public struct StrokeScore {
    public let strokeId: UUID
    public let strokeType: StrokeType
    public let phaseScores: [PhaseSegment]
    public let totalScore: Double
    public let subMetrics: [String: Double]
}

public struct VideoScore {
    public let strokes: [StrokeScore]
    public let forehandAvg: Double?
    public let backhandAvg: Double?
    public let overall: Double
}

public struct SessionGradingResult {
    public let bestForehandURL: URL
    public let bestBackhandURL: URL
    public let forehandScore: StrokeScore
    public let backhandScore: StrokeScore
    public let frameResults: [FramePoseResult]
    public let strokeSegments: [StrokeSegment]
    public let strokeScores: [StrokeScore]
    public let videoScore: VideoScore
}


