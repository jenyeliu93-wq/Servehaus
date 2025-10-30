//  GradingReportTabView.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/21/25.

// Views/GradingResult/GradingReportTabView.swift
import SwiftUI
import Foundation
import AVKit

/**
 This file defines the final user-facing report view for the grading pipeline, which includes scoring and report visualization.
 It presents detailed per-stroke video clips alongside their respective scores, culminating in the ServeHaus Index as an overall performance metric.
 
 The report integrates closely with the PoseVideoOverlayView, which provides visual overlays on the video clips to enhance user understanding of stroke mechanics.
 This view serves as the endpoint in the grading workflow, summarizing the analysis results in an intuitive and interactive interface.
 
 Highlight clips are already available directly via SessionGradingResult, so VideoClipExporter is no longer used.
 */

struct GradingReportTabView: View {
    let result: SessionGradingResult
    var onNewSession: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            sessionOverview
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    strokeHighlightSection(type: .forehand, highlightURL: result.bestForehandURL)
                    strokeHighlightSection(type: .backhand, highlightURL: result.bestBackhandURL)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            Button(action: {
                onNewSession?()
            }) {
                Text("New Session")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            setupSessionScores()
        }
    }
    
    // MARK: - Session Overview
    
    private var sessionOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
//            Text("Session Overview")
//                .font(.title2)
//                .bold()
//                .padding(.horizontal)
//            
            HStack(alignment: .top, spacing: 16) {
                // ServeHaus Index Capsule
                let rawScore = Int(result.videoScore.overall.rounded())
                let shownScore = displayFloor(rawScore)
                
                VStack {
                    if rawScore == 0 {
                        Text("Analyzing / No Groundstroke Detected")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    } else {
                        Text("\(shownScore)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    Text("ServeHaus Index")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 100)
                
                Spacer()
                
                // Radar chart now uses StrokeSegment-based aggregation for five key metrics
                RadarChartView(segments: result.strokeSegments)
                    .frame(width: 150, height: 150)
                    .opacity(0.75)
            }
            .padding(.horizontal)
            
            // Forehand and Backhand averages below the chart
            HStack(spacing: 24) {
                let forehandAvg = Int((result.videoScore.forehandAvg ?? 0).rounded())
                let backhandAvg = Int((result.videoScore.backhandAvg ?? 0).rounded())
                
                VStack {
                    Text("Forehand Avg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(forehandAvg)")
                        .font(.headline)
                        .bold()
                }
                VStack {
                    Text("Backhand Avg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(backhandAvg)")
                        .font(.headline)
                        .bold()
                }
                Spacer()
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Stroke Highlight Section
    
    private func strokeHighlightSection(type: StrokeType, highlightURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(type == .forehand ? "🎬 Forehand Highlight" : "🎬 Backhand Highlight")
                .font(.headline)
                .bold()
            
            VideoPlayerView(url: highlightURL)
                .frame(height: 180)
                .cornerRadius(10)
            
            // Score and feedback
            let avgScore = (type == .forehand ? result.videoScore.forehandAvg : result.videoScore.backhandAvg) ?? 0
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Score: \(Int(avgScore.rounded()))")
                    .font(.subheadline)
                    .bold()
                
                // Static placeholder for quick feedback
                Text("Quick Feedback: Keep your wrist steady and maintain smooth acceleration.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Key metrics: Acceleration / Impact / Completeness
                HStack(spacing: 16) {
                    metricView(name: "Acceleration", value: metricValue(for: type, key: "Acceleration"))
                    metricView(name: "Impact", value: metricValue(for: type, key: "Impact"))
                    metricView(name: "Completeness", value: metricValue(for: type, key: "Completeness"))
                }
                
                // Tip label for visual coaching feedback
                Text("🧠 Tip: Focus on smooth acceleration to improve stroke power and control.")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
            }
        }
    }
    
    private func metricView(name: String, value: Double) -> some View {
        VStack {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.2f", value))
                .font(.headline)
                .bold()
        }
        .frame(minWidth: 80)
    }
    
    private func metricValue(for type: StrokeType, key: String) -> Double {
        // Compute average metric value for the stroke type
        let strokes = result.videoScore.strokes.filter { $0.strokeType == type }
        let values = strokes.compactMap { $0.subMetrics[key] }
        guard !values.isEmpty else { return 0.0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
    // MARK: - Private Methods
    
    private func setupSessionScores() {
        // The data now maps from frame → stroke → video → UI
        // We aggregate all subMetrics from all strokes to compute session-level averages
        // subMetrics is now a dictionary [String: Double], so we compute averages accordingly
        
        var sessionScores = [String: Double]()
        
        // Collect all metric names across strokes
        let allMetricNames = Set(result.videoScore.strokes.flatMap { $0.subMetrics.keys })
        
        // Compute average score per metric across all strokes
        func average(for name: String) -> Double {
            let filtered = result.videoScore.strokes.compactMap { $0.subMetrics[name] }
            guard !filtered.isEmpty else { return 0.0 }
            return filtered.reduce(0, +) / Double(filtered.count)
        }
        
        for name in allMetricNames {
            sessionScores[name] = average(for: name)
        }
        
        // This function could be used to update UI or state if needed
        // Currently no state object, so this is a placeholder for future extension
    }
    
    // Helper function to mimic previous displayFloor behavior
    private func displayFloor(_ score: Int) -> Int {
        // Example: floor to nearest multiple of 5
        return (score / 5) * 5
    }
}

// VideoPlayerView now applies slow motion playback at 0.5× rate using AVPlayer.playImmediately(atRate:)
// This change affects only local playback within this tab view and does not affect the data pipeline.
struct VideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer? = nil
    
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let avPlayer = AVPlayer(url: url)
                avPlayer.playImmediately(atRate: 0.5)
                player = avPlayer
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
            .cornerRadius(10)
    }
}
