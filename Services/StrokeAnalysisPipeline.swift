//
//  StrokeAnalysisPipeline.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/21/25.
//

import Foundation
import AVFoundation
import Vision



// MARK: - StrokeAnalysisPipeline Orchestrator
// Changed visibility from public to internal to resolve “internal type used in public declaration” issue.
class StrokeAnalysisPipeline {
    /// Orchestrates the full stroke analysis pipeline.
    /// - Parameters:
    ///   - videoURL: The URL of the video to analyze.
    ///   - progressCallback: Reports progress (0.0 - 1.0).
    /// - Returns: A SessionGradingResult containing all analysis data.
    static func analyze(videoURL: URL, progressCallback: @escaping (Double) -> Void) async throws -> SessionGradingResult {
        // MARK: Step 1 - Extract frame poses (FramePoseResult)
        await MainActor.run { progressCallback(0.05) }
        let frameResults: [FramePoseResult] = try await VideoPoseExtractor.extractPoses(from: videoURL)
        await MainActor.run { progressCallback(0.20) }

        // Guard for insufficient frames
        // Guard for insufficient frames
        guard frameResults.count > 1 else {
            print("⚠️ No sufficient frames found — cannot analyze video.")
            await MainActor.run { progressCallback(1.0) }
            return SessionGradingResult(
                bestForehandURL: videoURL,
                bestBackhandURL: videoURL,
                forehandScore: StrokeScore(strokeId: UUID(), strokeType: .forehand, phaseScores: [], totalScore: 0, subMetrics: [:]),
                backhandScore: StrokeScore(strokeId: UUID(), strokeType: .backhand, phaseScores: [], totalScore: 0, subMetrics: [:]),
                frameResults: [],
                strokeSegments: [],
                strokeScores: [],
                videoScore: VideoScore(strokes: [], forehandAvg: 0.0, backhandAvg: 0.0, overall: 0.0)
            )
        }

        // MARK: Step 2 - Extract motion-level features (MotionPoint)
        let motionPoints: [MotionPoint] = await withTaskGroup(of: MotionPoint?.self) { group in
            for i in 1..<frameResults.count {
                let prev = frameResults[i - 1]
                let next = frameResults[i]
                group.addTask {
                    return await PoseAnalysisService.computeMotionPoint(prev: prev, next: next)
                }
            }
            var collected: [MotionPoint] = []
            for await mp in group {
                if let mp = mp { collected.append(mp) }
            }
            return collected
        }
        await MainActor.run { progressCallback(0.35) }

        // MARK: Step 3 - Segment complete strokes (StrokeSegment, with embedded phases)
//        let strokeSegments: [StrokeSegment] = await segmentStrokes(from: motionPoints)
        let strokeSegments: [StrokeSegment] = await MotionFeaturePipeline.segmentStrokes(from: motionPoints)
        await MainActor.run { progressCallback(0.55) }

        // MARK: Step 4 - Compute stroke and video scores (StrokeScore + VideoScore)
        let videoScore: VideoScore = StrokeScoringService.scoreStrokes(strokeSegments)

        // Extract individual stroke scores
        let strokeScores: [StrokeScore] = videoScore.strokes

        // MARK: Step 5 - Aggregate video-level score (VideoScore)
        let forehandScores = strokeScores.filter { $0.strokeType == .forehand }
        let backhandScores = strokeScores.filter { $0.strokeType == .backhand }

        let forehandAvg = forehandScores.map(\.totalScore).averageOrZero()
        let backhandAvg = backhandScores.map(\.totalScore).averageOrZero()
        let overallAvg = (forehandAvg + backhandAvg) /
            (forehandScores.isEmpty || backhandScores.isEmpty ? 1.0 : 2.0)

        print("Overall average: \(overallAvg)")


        // MARK: Step 6 - Export best clips for each stroke type
        async let bestForehandURL = exportBestClip(for: .forehand, from: strokeSegments, using: strokeScores, videoURL: videoURL)
        async let bestBackhandURL = exportBestClip(for: .backhand, from: strokeSegments, using: strokeScores, videoURL: videoURL)
        let (finalForehandURL, finalBackhandURL) = await (bestForehandURL, bestBackhandURL)

        // MARK: Step 7 - Return complete session result
        return SessionGradingResult(
            bestForehandURL: finalForehandURL,
            bestBackhandURL: finalBackhandURL,
            forehandScore: forehandScores.first ?? StrokeScore(strokeId: UUID(), strokeType: .forehand, phaseScores: [], totalScore: 0, subMetrics: [:]),
            backhandScore: backhandScores.first ?? StrokeScore(strokeId: UUID(), strokeType: .backhand, phaseScores: [], totalScore: 0, subMetrics: [:]),
            frameResults: frameResults,
            strokeSegments: strokeSegments,
            strokeScores: strokeScores,
            videoScore: videoScore
        )
    }
    
    /// Helper to export the best clip for a given stroke type based on highest score.
    private static func exportBestClip(for strokeType: StrokeType, from strokeSegments: [StrokeSegment], using strokeScores: [StrokeScore], videoURL: URL) async -> URL {
        struct StrokeEvent {
            let type: StrokeType
            let startTime: Double
            let peakTime: Double
            let endTime: Double
        }
        
        let hasStroke = strokeSegments.contains { $0.type == strokeType }
        guard hasStroke else { return videoURL }

        let bestIndex = strokeSegments
            .enumerated()
            .filter { $0.element.type == strokeType }
            .max(by: { strokeScores[$0.offset].totalScore < strokeScores[$1.offset].totalScore })?.offset

        guard let bestIndex = bestIndex else { return videoURL }

        let seg = strokeSegments[bestIndex]
        let asset = AVURLAsset(url: videoURL)
        let timeRange = CMTimeRange(start: seg.timeRange.lowerBound, end: seg.timeRange.upperBound)
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = strokeType == .forehand ? "forehand_highlight.mov" : "backhand_highlight.mov"
        let outputURL = tempDir.appendingPathComponent(fileName)
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return videoURL
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = timeRange
        exportSession.shouldOptimizeForNetworkUse = true
        
//        return await withCheckedContinuation { continuation in
//            Task.detached {
//                for await state in exportSession.states(updateInterval: 0.2) {
//                    if case .completed = state.status {
//                        continuation.resume(returning: outputURL)
//                        return
//                    } else if case .failed = state.status {
//                        continuation.resume(returning: videoURL)
//                        return
//                    } else if case .cancelled = state.status {
//                        continuation.resume(returning: videoURL)
//                        return
//                    }
//                }
//            }
        return await withCheckedContinuation { continuation in
            Task.detached {
                do {
                    try await exportSession.export(to: outputURL, as: .mov)
                    continuation.resume(returning: outputURL)
                } catch {
                    print("Export failed: \(error.localizedDescription)")
                    continuation.resume(returning: videoURL)
                }
            }
        }
        
    }
}

private extension Array where Element == Double {
    func averageOrZero() -> Double {
        guard !isEmpty else { return 0.0 }
        return reduce(0, +) / Double(count)
    }
}
