//
//  RadarChartView.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/21/25.
//

import SwiftUI

struct RadarChartView: View {
    struct AxisValue: Identifiable {
        let id = UUID()
        let label: String
        let value: Double // 0..100
    }
    
    let axes: [AxisValue] // 5 items
    
    init(segments: [StrokeSegment]) {
        self.axes = RadarChartView.computeAxes(from: segments)
    }
    
    var body: some View {
        GeometryReader { geo in
            let n = axes.count
            let radius = min(geo.size.width, geo.size.height) * 0.4
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            
            ZStack {
                // Draw spokes
                ForEach(0..<n, id: \.self) { i in
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point(for: i, total: n, radius: radius, center: center))
                    }
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
                
                // Draw concentric polygons (rings)
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    Polygon(sides: n, radius: radius * CGFloat(fraction), center: center)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                
                // Draw filled polygon representing data
                let points = (0..<n).map { i -> CGPoint in
                    let normalized = max(0, min(1, axes[i].value / 100))
                    return point(for: i, total: n, radius: radius * CGFloat(normalized), center: center)
                }
                PolygonPath(points: points)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: axes.map { color(for: $0.value) }),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .opacity(0.25)
                    )
                
                // Draw value labels near polygon points
                ForEach(0..<n, id: \.self) { i in
                    let normalized = max(0, min(1, axes[i].value / 100))
                    let valuePoint = point(for: i, total: n, radius: radius * CGFloat(normalized), center: center)
                    Text(String(format: "%.0f", axes[i].value))
                        .font(.caption2)
                        .foregroundColor(color(for: axes[i].value))
                        .position(valuePoint)
                }
                
                // Draw axis labels outside polygon
                ForEach(0..<n, id: \.self) { i in
                    let labelPoint = point(for: i, total: n, radius: radius * 1.15, center: center)
                    Text(axes[i].label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(labelPoint)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func point(for index: Int, total: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = (Double(index) / Double(total)) * 2 * .pi - .pi / 2
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }
    
    private func color(for value: Double) -> Color {
        switch value {
        case 70...:
            return .green
        case 40..<70:
            return .yellow
        default:
            return .red
        }
    }
    
    private static func computeAxes(from segments: [StrokeSegment]) -> [AxisValue] {
        let metrics = [
            "Rotation Efficiency",
            "Timing Consistency",
            "Energy Transfer",
            "Balance & Posture",
            "Completeness"
        ]
        
        func average(for key: String) -> Double {
            let values = segments.compactMap { $0.aggregates[key] }
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }
        
        return metrics.map { metric in
            AxisValue(label: metric, value: average(for: metric))
        }
    }
}

private struct Polygon: Shape {
    let sides: Int
    let radius: CGFloat
    let center: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard sides > 2 else { return path }
        
        let points = (0..<sides).map { i -> CGPoint in
            let angle = (Double(i) / Double(sides)) * 2 * .pi - .pi / 2
            return CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
        }
        
        path.addLines(points + [points.first!])
        return path
    }
}

private struct PolygonPath: Shape {
    let points: [CGPoint]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: points[0])
        
        return path
    }
}
