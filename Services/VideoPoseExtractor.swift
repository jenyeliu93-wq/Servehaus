//
//  VideoPoseExtractor.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/21/25.
//
//  VideoPoseExtractor is solely responsible for extracting and normalizing pose frames from video sources.
//  Each extracted frame is represented as a FramePoseResult which includes normalized joint coordinates,
//  confidence scores, timing metadata, and a videoId for session-level traceability.
//
//  The extracted frame-level pose data forms the input to the downstream unified data pipeline:
//  FramePoseResult → MotionPoint → StrokeSegment → PhaseSegment → StrokeScore → VideoScore.
//
//  This file focuses exclusively on frame extraction and normalization utilities,
//  while all biomechanical computations and stroke detection are handled externally.
//

import Foundation
import AVFoundation
import Vision
import CoreGraphics


//
//  VideoPoseExtractor
//  Core role: Extracts normalized joint coordinates from video frames using Vision framework.
//  Output: Array of FramePoseResult representing frame-level pose data with video-level traceability.
//
//  This data serves as the foundational input for the downstream biomechanical and stroke analysis pipeline,
//  ensuring high granularity and temporal consistency.
//
//  Note: Biomechanical and stroke logic is implemented outside this file.
//
final class VideoPoseExtractor {
    /// Extracts human body poses from a video file by sampling frames uniformly and analyzing each frame asynchronously.
    ///
    /// This method samples frames every `frameInterval` seconds up to a maximum duration of `maxDuration` seconds,
    /// detects poses using Vision, and normalizes joint coordinates relative to the frame size.
    ///
    /// - Parameters:
    ///   - videoURL: URL of the local video file to analyze.
    ///   - frameInterval: Time interval in seconds between sampled frames. Default is 0.05s.
    ///   - maxDuration: Maximum duration in seconds to analyze from the video. Default is 30s.
    ///   - progressCallback: Optional closure called with progress updates (0.0 to 1.0) for UI feedback.
    /// - Returns: An array of `FramePoseResult` containing normalized joint data, confidence scores,
    ///            timing metadata, and videoId for each sampled frame.
    /// - Note: The returned pose data is consumed by the unified downstream pipeline for biomechanical computation and stroke analysis.
    static func extractPoses(
        from videoURL: URL,
        frameInterval: Double = 0.05,
        maxDuration: Double = 60.0,
        progressCallback: ((Double) -> Void)? = nil
    ) async throws -> [FramePoseResult] {
        print("🎥 Using robust extraction mode (max 30s)")
        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else {
            print("⚠️ Invalid or zero-duration asset")
            return []
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var results: [FramePoseResult] = []
        let analysisDuration = min(duration, maxDuration)
        let totalFrames = Int(analysisDuration / frameInterval)
        var frameCount = 0
        let videoId = UUID() // Unique ID for this video extraction session

        var currentTime: Double = 0.0
        while currentTime < analysisDuration {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            do {
                let cgImage = try await withCheckedThrowingContinuation { continuation in
                    generator.generateCGImageAsynchronously(for: time) { image, _, error in
                        if let image = image {
                            continuation.resume(returning: image)
                        } else if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: NSError(domain: "VideoPoseExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown frame extraction error"]))
                        }
                    }
                }

                guard let poses = try? await PoseAnalysisService.detectPoses(in: cgImage),
                      !poses.isEmpty else {
                    currentTime += frameInterval
                    frameCount += 1
                    let progress = min(Double(frameCount) / Double(totalFrames), 1.0)
                    await MainActor.run {
                        progressCallback?(progress)
                    }
                    continue
                }

                if let mainPose = poses.first {
                    let points = PoseAnalysisService.jointPoints(from: mainPose)
                    let orientation = CGImagePropertyOrientation.up
                    let normalizedJoints = normalizeLandmarkPoints(
                        points,
                        orientation: orientation,
                        frameSize: CGSize(width: cgImage.width, height: cgImage.height)
                    )
                    let confidences = PoseAnalysisService.jointConfidences(from: mainPose)
                    let meta = FrameTimeMeta(
                        frameIndex: frameCount,
                        timestampSec: time.seconds,
                        frameInterval: frameInterval,
                        isInterpolated: false
                    )
                    results.append(FramePoseResult(
                        videoId: videoId,
                        time: time,
                        joints: normalizedJoints,
                        confidences: confidences,
                        timeMeta: meta
                    ))
                }

            } catch {
                print("⚠️ Frame extraction failed at \(time.seconds): \(error.localizedDescription)")
            }

            frameCount += 1
            let progress = min(Double(frameCount) / Double(totalFrames), 1.0)
            await MainActor.run {
                progressCallback?(progress)
            }

            currentTime += frameInterval
        }

        print("✅ Pose extraction finished, total frames processed: \(results.count)")
        return results
    }

    /// Normalizes joint landmark points according to the image orientation and frame size.
    ///
    /// This adjustment ensures joint coordinates are consistent and comparable across frames regardless of orientation.
    ///
    /// - Parameters:
    ///   - points: Dictionary mapping joint names to CGPoint coordinates in Vision coordinate space.
    ///   - orientation: The orientation of the CGImage to adjust coordinates accordingly.
    ///   - frameSize: The size of the frame image (width and height) for normalization.
    /// - Returns: A dictionary of joint names to normalized CGPoint coordinates (values between 0.0 and 1.0).
    /// - Note: Normalized points are used downstream for biomechanical calculations and visualization.
    private static func normalizeLandmarkPoints(
        _ points: [VNHumanBodyPoseObservation.JointName: CGPoint],
        orientation: CGImagePropertyOrientation,
        frameSize: CGSize
    ) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var normalized: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in points {
            var x = CGFloat(point.x)
            var y = CGFloat(point.y)
            switch orientation {
            case .up:
                break
            case .right:
                swap(&x, &y)
                y = 1 - y
            case .left:
                swap(&x, &y)
                x = 1 - x
            case .down:
                x = 1 - x
                y = 1 - y
            default:
                break
            }
            normalized[joint] = CGPoint(x: x, y: y)
        }
        return normalized
    }

}

extension PoseAnalysisService {
    /// Extracts confidence scores for a predefined set of human body joints from a Vision pose observation.
    ///
    /// - Parameter observation: A `VNHumanBodyPoseObservation` containing detected joint information.
    /// - Returns: A dictionary mapping joint names to confidence scores (0.0 to 1.0).
    /// - Note: Confidence scores inform the reliability of joint detections and are used in stroke and pose quality assessments.
    static func jointConfidences(from observation: VNHumanBodyPoseObservation) -> [VNHumanBodyPoseObservation.JointName: Double] {
        var result: [VNHumanBodyPoseObservation.JointName: Double] = [:]
        let joints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .root,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]
        for joint in joints {
            if let point = try? observation.recognizedPoint(joint) {
                result[joint] = Double(point.confidence)
            }
        }
        return result
    }
}
