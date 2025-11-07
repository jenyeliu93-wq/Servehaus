//
//  PoseVideoOverlayView.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/19/25.
//

import SwiftUI
import AVKit
import Vision
import CoreMedia
import Combine
import Charts

struct PoseVideoOverlayView: View {
    let videoURL: URL
    @State private var player: AVPlayer
    @State private var extractedFrames: [FramePoseResult] = []
    @State private var isAnalyzing = true
    @State private var currentJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @State private var activeRegion: CGRect? = nil
    @State private var analysisProgress: Double = 0.0
    @State private var sessionResult: SessionGradingResult? = nil
    @State private var showResults: Bool = false
    @State private var motionPoints: [MotionPoint] = []
    @State private var phaseSegments: [PhaseSegment] = []
    @State private var selectedMetric: String = "energy"
    @State private var isScrubbing = false
    @State private var lastSeekTime = Date(timeIntervalSince1970: 0)

    // All available metric names for trend charts
    private let allMetricNames: [String] = [
        "shoulderSpan",
        "hipSpan",
        "footSpan",
        "shoulderCoilFactor",
        "hipCoilFactor",
        "wristHeightRel",
        "wristXOffsetRel",
        "forearmAngularSpeed",
        "wristLinearSpeed",
//        "rotSign",
        "COMspeed",
        "handSpeedRatio",
        "energyRearHybrid"
    ]
    @State private var currentTimeSeconds: Double = 0.0
    @State private var timeObserver: Any?
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject var sessionManager: SessionManager

    var onAnalysisComplete: ((SessionGradingResult) -> Void)? = nil

//    private static var analyzedVideos: Set<URL> = []
    internal static var analyzedVideos: Set<URL> = []

    init(videoURL: URL?, onAnalysisComplete: ((SessionGradingResult) -> Void)? = nil) {
        if let safeURL = videoURL, FileManager.default.fileExists(atPath: safeURL.path), !safeURL.path.isEmpty {
            self.videoURL = safeURL
            _player = State(initialValue: AVPlayer(url: safeURL))
        } else {
            self.videoURL = URL(fileURLWithPath: "/dev/null")
            _player = State(initialValue: AVPlayer())
        }
        self.onAnalysisComplete = onAnalysisComplete
    }

    var body: some View {
        Group {
            if sessionManager.videoURL == nil {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "film.stack")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.gray)
                    Text("No video available")
                        .font(.headline)
                    Text("Please return to the Video tab to upload or record a video.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 16) {
                            // Video and overlay section
                            ZStack(alignment: .topLeading) {
                                // Video is the back layer
                                VideoPlayer(player: player)
                                    .frame(height: geometry.size.height * 0.65)
                                    .onAppear {
                                        if player.currentItem == nil {
                                            player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
                                        player.isMuted = true   // 🔇 Mute by default

                                        }

                                        if sessionManager.phase == .ready && !sessionManager.isAnalyzing {
                                            sessionManager.isAnalyzing = true
                                            sessionManager.phase = .analyzing
                                            withAnimation(.easeInOut(duration: 0.8)) {
                                                analysisProgress = 0.01
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                analyzeVideo()
                                            }
                                        }

                                        player.play()
                                        attachTimeObserver()
                                    }
                                    .onChange(of: videoURL) {_,newURL in
                                        player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
                                        player.seek(to: .zero, completionHandler: { _ in
                                            reconnectOverlayIfNeeded()
                                        })
                                        player.play()
                                        isAnalyzing = true
                                        analysisProgress = 0.0
                                        extractedFrames.removeAll()
                                        motionPoints.removeAll()
                                        phaseSegments.removeAll()
                                        analyzeVideo()
                                    }
                                    .allowsHitTesting(true)
                                    .onDisappear {
                                        player.pause()
                                        detachTimeObserver()
                                    }
                                    .padding(.top, geometry.safeAreaInsets.top + 4)
                                    .padding(.bottom, geometry.safeAreaInsets.bottom + 4)
                                    .zIndex(0)

                                // Pose overlay and stroke info above video, below controls
                                Group {
                                    PoseOverlayView(joints: currentJoints, activeRegion: activeRegion,sessionID: sessionManager.sessionUUID
)
                                    // Stroke Info
                                    VStack(alignment: .leading) {
                                        if let activePhase = phaseSegments.first(where: { phase in
                                            phase.frames.contains { mp in
                                                abs(mp.time.seconds - player.currentTime().seconds) < 0.05
                                            }
                                        }),
                                        let strokeType = sessionResult?.strokeSegments.first(where: { $0.phases.contains(where: { $0.phase == activePhase.phase }) })?.type {
                                            Text("🎾 Stroke: \(strokeType == .forehand ? "Forehand" : "Backhand")")
                                                .font(.headline)
                                                .foregroundColor(.green)
                                            Text("Phase: \(activePhase.phase.rawValue.capitalized)")
                                                .font(.subheadline)
                                                .foregroundColor(.yellow)
                                        }
                                        Spacer()
                                    }
                                    .padding(.top, 60)
                                    .padding(.leading, 20)
                                    .allowsHitTesting(false)
                                }
                                .allowsHitTesting(false)
                                .zIndex(0)
                            }
                            // Overlay for analysis progress
                            .overlay(
                                Group {
                                    if isAnalyzing  {
                                        VStack(spacing: 8) {
                                            ProgressView(value: analysisProgress)
                                                .progressViewStyle(LinearProgressViewStyle())
                                                .frame(width: 200)
                                            Text(String(format: "Analyzing video… %.0f%%", analysisProgress * 100))
                                                .font(.footnote)
                                                .foregroundColor(.white)
                                        }
                                        .padding()
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(12)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .allowsHitTesting(false)
                            )

                            // Metric Trends Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("📊 Metric Trends")
                                    .font(.headline)
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: 24) {
                                        ForEach(allMetricNames, id: \.self) { metric in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(metric)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                Group {
                                                    if isAnalyzing || motionPoints.isEmpty {
                                                        // Show loading/placeholder while analyzing or no data
                                                        HStack {
                                                            Spacer()
                                                            VStack(spacing: 10) {
                                                                ProgressView()
                                                                    .progressViewStyle(CircularProgressViewStyle())
                                                                Text(isAnalyzing ? "Analyzing metrics…" : "Loading metrics…")
                                                                    .font(.caption)
                                                                    .foregroundColor(.secondary)
                                                            }
                                                            Spacer()
                                                        }
                                                        .frame(height: 200)
                                                    } else {
                                                        MetricTrendChartView(
                                                            motionPoints: motionPoints,
                                                            phaseSegments: phaseSegments,
                                                            selectedMetric: metric,
                                                            currentTime: currentTimeSeconds,
                                                            scrubTime: $currentTimeSeconds,
                                                            isScrubbing: $isScrubbing,
                                                            player: player,
                                                            lastSeekTime: $lastSeekTime,
                                                            reconnectOverlayIfNeeded: reconnectOverlayIfNeeded
                                                        )
                                                        .id(metric + "_\(motionPoints.count)")
                                                        .frame(height: 200)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                            .padding(.horizontal)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 8)
                    }
                }
            }
        }
    }

    // MARK: - Video Analysis
    private func analyzeVideo() {
        guard !Self.analyzedVideos.contains(videoURL) else {
            print("⚠️ Skipping duplicate analysis for \(videoURL.lastPathComponent)")
            return
        }
        Self.analyzedVideos.insert(videoURL)
        Task.detached(priority: .userInitiated) {
            // Set isAnalyzing to true on main thread before starting analysis
            await MainActor.run {
                sessionManager.isAnalyzing = true
            }
            do {
                let frames = try await VideoPoseExtractor.extractPoses(from: videoURL, frameInterval: 0.3) { progress in
                    DispatchQueue.main.async {
//                        analysisProgress = progress * 0.5
                        smoothProgress(to: progress * 0.5)
                    }
                }
                await MainActor.run {
                    self.extractedFrames = frames
                }

                let result = try await StrokeAnalysisPipeline.analyze(
                    videoURL: videoURL,
                    progressCallback: { progress in
                        DispatchQueue.main.async {
                            let target = 0.5 + 0.5 * progress
                            smoothProgress(to: target)
                        }
                    }
                )
                await MainActor.run {
                    sessionManager.result = result
                    sessionManager.phase = .completed
                    sessionResult = result
                    motionPoints = result.strokeSegments.flatMap { $0.frames }
                    phaseSegments = result.strokeSegments.flatMap { $0.phases }
                    analysisProgress = 1.0
                    self.isAnalyzing = false
                    player.seek(to: .zero)
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                }
                print("Pose extraction failed: \(error)")
            }
        }
    }

    private func smoothProgress(to target: Double) {
        withAnimation(.linear(duration: 0.5)) {
            analysisProgress = target
        }
    }

    // MARK: - Time Observer (Frame-accurate sync)
    private func attachTimeObserver() {
        // 30 fps observer for near frame-accurate callbacks
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTimeSeconds = time.seconds
            updatePose(for: time)
        }
        // Watch for currentTimeSeconds changes and seek only if not scrubbing
        // (This is typically handled by drag gestures now)
        // If you want to add .onChange for currentTimeSeconds, make sure to check isScrubbing
        // (No explicit .onChange here; handled in chart gesture)
    }

    private func detachTimeObserver() {
        if let token = timeObserver {
            player.removeTimeObserver(token)
            timeObserver = nil
        }
    }

    // MARK: - Pose Update
    private func updatePose(for currentTime: CMTime) {
        guard !isAnalyzing else { return }
        guard !isScrubbing else { return }
        let currentSeconds = currentTime.seconds
        if let closestFrame = extractedFrames.min(by: { abs($0.time.seconds - currentSeconds) < abs($1.time.seconds - currentSeconds) }) {
            DispatchQueue.main.async {
                currentJoints = closestFrame.joints
            }
        }
    }

    private func reconnectOverlayIfNeeded() {
        if player.currentItem?.outputs.isEmpty ?? true {
            let newOutput = AVPlayerItemVideoOutput()
            player.currentItem?.add(newOutput)
        }
    }
}

struct MetricTrendChartView: View {
    let motionPoints: [MotionPoint]
    let phaseSegments: [PhaseSegment]
    let selectedMetric: String
    let currentTime: Double
    @Binding var scrubTime: Double
    @Binding var isScrubbing: Bool
    var player: AVPlayer
    @Binding var lastSeekTime: Date
    var reconnectOverlayIfNeeded: () -> Void
    var body: some View {
        GeometryReader { geo in
            Chart {
                ForEach(Array(motionPoints.enumerated()), id: \.offset) { i, mp in
                    if let value = valueFor(metric: selectedMetric, in: mp) {
                        LineMark(
                            x: .value("Time", mp.time.seconds),
                            y: .value(selectedMetric, value)
                        )
                        .foregroundStyle(color(for: selectedMetric))
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                }
                // Live playhead synced to video
                RuleMark(x: .value("Playhead", currentTime))
                    .foregroundStyle(Color.red)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        if let live = interpolatedValue(at: currentTime) {
                            Text(String(format: "%@ %.3f",
                                        selectedMetric == "energy" ? "E" :
                                        selectedMetric == "wristOffset" ? "W" :
                                        selectedMetric == "rotSign" ? "R" : "S",
                                        live))
                            .font(.caption2)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                        }
                    }
            }
            .chartYScale(domain: yDomain(for: selectedMetric))
            .animation(.linear(duration: 0.033), value: currentTime)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard let first = motionPoints.first, let last = motionPoints.last else { return }
                        let width = geo.size.width - 32
                        let fraction = max(0, min(1, value.location.x / width))
                        let newTime = first.time.seconds + fraction * (last.time.seconds - first.time.seconds)
                        scrubTime = newTime
                        isScrubbing = true
                        if Date().timeIntervalSince(lastSeekTime) > 0.1 {
                            player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600), completionHandler: { _ in
                                reconnectOverlayIfNeeded()
                            })
                            lastSeekTime = Date()
                        }
                    }
                    .onEnded { _ in
                        isScrubbing = false
                        reconnectOverlayIfNeeded()
                    }
            )
        }
    }
    private func autoDomain(for values: [Double]) -> ClosedRange<Double> {
        guard let min = values.min(), let max = values.max(), min != max else { return -1...1 }
        let padding = (max - min) * 0.1
        return (min - padding)...(max + padding)
    }
    private func yDomain(for metric: String) -> ClosedRange<Double> {
        let vals = motionPoints.compactMap { valueFor(metric: metric, in: $0) }
        guard let ymin = vals.min(), let ymax = vals.max(), ymin != ymax else {
            return -1...1
        }
        let padding = (ymax - ymin) * 0.1
        return (ymin - padding)...(ymax + padding)
    }
    private func valueFor(metric: String, in mp: MotionPoint) -> Double? {
        switch metric {
        case "shoulderSpan": return Double(mp.shoulderSpan)
        case "hipSpan": return Double(mp.hipSpan)
        case "footSpan": return Double(mp.footSpan)
        case "shoulderCoilFactor": return Double(mp.shoulderCoilFactor)
        case "hipCoilFactor": return Double(mp.hipCoilFactor)
        case "wristHeightRel": return Double(mp.wristHeightRel)
        case "wristXOffsetRel": return Double(mp.wristXOffsetRel)
        case "forearmAngularSpeed": return Double(mp.forearmAngularSpeed)
        case "wristLinearSpeed": return Double(mp.wristLinearSpeed)
        case "COMspeed": return Double(mp.comSpeed)
        case "handSpeedRatio": return Double(mp.handSpeedRatio)
        case "energyRearHybrid": return Double(mp.energyRearHybrid)
        default: return nil
        }
    }

    private func color(for metric: String) -> Color {
        switch metric {
        case "shoulderSpan": return .teal
        case "hipSpan": return .cyan
        case "footSpan": return .brown
        case "shoulderCoilFactor": return .orange
        case "hipCoilFactor": return .yellow
        case "wristHeightRel": return .mint
        case "wristXOffsetRel": return .indigo
        case "forearmAngularSpeed": return .pink
        case "wristLinearSpeed": return .blue
        case "rotSign": return .purple
        case "COMspeed": return .green
        case "handSpeedRatio": return .red
        case "energyRearHybrid": return .gray
        default: return .gray
        }
    }
    // Linear interpolation of selected metric at arbitrary time (seconds)
    private func interpolatedValue(at t: Double) -> Double? {
        guard motionPoints.count >= 2 else { return nil }
        // Find the surrounding samples
        let sorted = motionPoints.sorted { $0.time.seconds < $1.time.seconds }
        if t <= sorted.first!.time.seconds { return valueFor(metric: selectedMetric, in: sorted.first!) }
        if t >= sorted.last!.time.seconds { return valueFor(metric: selectedMetric, in: sorted.last!) }
        // Binary search or linear scan (array is small)
        for i in 1..<sorted.count {
            let t0 = sorted[i-1].time.seconds
            let t1 = sorted[i].time.seconds
            if t0 ... t1 ~= t {
                guard let v0 = valueFor(metric: selectedMetric, in: sorted[i-1]),
                      let v1 = valueFor(metric: selectedMetric, in: sorted[i]) else { return nil }
                let u = (t - t0) / max(1e-6, (t1 - t0))
                return v0 + u * (v1 - v0)
            }
        }
        return nil
    }
}
