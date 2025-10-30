////
////  Untitled.swift
////  ServiceHausAI_test
////
////  Created by Ye Liu on 10/27/25.
////
//
//// 1️⃣ Raw pose frame
//struct FramePoseResult: Identifiable {
//    let id = UUID()
//    let videoId: UUID
//    let time: CMTime
//    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
//    let confidences: [VNHumanBodyPoseObservation.JointName: Double]
//    let timeMeta: FrameTimeMeta?
//}
//
//// 2️⃣ Motion features (enhanced)
//public struct MotionPoint {
//    public let time: CMTime
//    public let frameId: UUID
//    public let energy: CGFloat
//    public let coilFactor: CGFloat       // NEW: shoulder/hip span delta
//    public let rotSign: CGFloat          // kept for side-view weighting
//    public let shoulderSpan: CGFloat
//    public let hipSpan: CGFloat
//    public let wristXOffsetRel: CGFloat
//    public let wristHeightRel: CGFloat
//    public let sepDeg: CGFloat
//}
//
//// 3️⃣ Stroke segment with embedded phases
//public struct StrokeSegment {
//    public let id: UUID
//    public var type: StrokeType
//    public let timeRange: ClosedRange<CMTime>
//    public let frames: [MotionPoint]
//    public let phases: [PhaseSegment]    // NEW: merged here
//    public let aggregates: [String: Double]
//    public let confidence: Double
//}
//
//public struct PhaseSegment {
//    public let phase: StrokeSubPhase
//    public let confidence: Double
//    public let frames: [MotionPoint]
//    public let metrics: [String: Double]
//    public let score: Double
//    public let formula: String
//}
//
//// 4️⃣ Scores
//struct StrokeScore {
//    let strokeId: UUID
//    let strokeType: StrokeType
//    let phaseScores: [PhaseSegment]
//    let totalScore: Double
//    let subMetrics: [String: Double]
//}
//
//struct VideoScore {
//    let strokes: [StrokeScore]
//    let forehandAvg: Double?
//    let backhandAvg: Double?
//    let overall: Double
//}
//
//struct SessionGradingResult {
//    let bestForehandURL: URL
//    let bestBackhandURL: URL
//    let forehandScore: StrokeScore
//    let backhandScore: StrokeScore
//    let frameResults: [FramePoseResult]
//    let strokeSegments: [StrokeSegment]
//    let strokeScores: [StrokeScore]
//    let videoScore: VideoScore
//}
