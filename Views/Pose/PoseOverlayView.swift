//
//  PoseOverlayView.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/17/25.
//

import SwiftUI
import Vision

struct PoseOverlayView: View {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let activeRegion: CGRect?
    let sessionID: UUID

    @State private var displayedJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

    private func sanitized(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        joints.filter { _, point in
            point.x.isFinite && point.y.isFinite
        }
    }

    var body: some View {
        GeometryReader { geo in
            let safeJoints = sanitized(displayedJoints)
            ZStack {
                // Joints (red dots)
                ForEach(Array(safeJoints.keys), id: \.self) { joint in
                    if let point = safeJoints[joint] {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .position(convert(point, in: geo))
                    }
                }

                // Add joint labels for key points
                let labeledJoints: [VNHumanBodyPoseObservation.JointName: String] = [
                    .leftShoulder: "LS",
                    .rightShoulder: "RS",
                    .leftElbow: "LE",
                    .rightElbow: "RE",
                    .leftHip: "LH",
                    .rightHip: "RH",
                    .leftKnee: "LK",
                    .rightKnee: "RK",
                    .leftAnkle: "LA",
                    .rightAnkle: "RA",
                    .leftWrist: "LW",
                    .rightWrist: "RW"
                ]

                ForEach(Array(labeledJoints.keys), id: \.self) { joint in
                    if let point = safeJoints[joint], let label = labeledJoints[joint] {
                        Text(label)
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.white)
                            .padding(2)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .position(convert(point, in: geo))
                            .offset(y: -10)
                    }
                }

                // Connect key joints with lines
                Path { path in
                    func connect(_ a: VNHumanBodyPoseObservation.JointName, _ b: VNHumanBodyPoseObservation.JointName) {
                        if let pa = safeJoints[a], let pb = safeJoints[b] {
                            path.move(to: convert(pa, in: geo))
                            path.addLine(to: convert(pb, in: geo))
                        }
                    }
                    connect(.leftShoulder, .leftElbow)
                    connect(.leftElbow, .leftWrist)
                    connect(.rightShoulder, .rightElbow)
                    connect(.rightElbow, .rightWrist)
                    connect(.leftHip, .leftKnee)
                    connect(.leftKnee, .leftAnkle)
                    connect(.rightHip, .rightKnee)
                    connect(.rightKnee, .rightAnkle)
                    connect(.leftShoulder, .rightShoulder)
                    connect(.leftHip, .rightHip)
                    connect(.rightShoulder, .rightHip)
                    connect(.leftShoulder, .leftHip)
                }
                .stroke(Color.blue, lineWidth: 2)
            }
            .id(sessionID)
            .onValueChange(of: sessionID) { _ in
                displayedJoints = [:]
            }
            .onValueChange(of: joints) { newJoints in
                displayedJoints = newJoints
            }
            .task {
                displayedJoints = joints
            }
        }
    }

    private func convert(_ point: CGPoint, in geo: GeometryProxy) -> CGPoint {
        let width = max(geo.size.width, 1)
        let height = max(geo.size.height, 1)

        var x: CGFloat
        var y: CGFloat

        if var box = activeRegion, box.width > 0, box.height > 0 {
            // Clamp activeRegion to [0,1]
            box.origin.x = min(max(box.origin.x, 0), 1)
            box.origin.y = min(max(box.origin.y, 0), 1)
            box.size.width = min(max(box.size.width, 0), 1 - box.origin.x)
            box.size.height = min(max(box.size.height, 0), 1 - box.origin.y)

            x = (point.x - box.minX) / box.width * width
            y = (1 - (point.y - box.minY) / box.height) * height
        } else {
            x = point.x * width
            y = (1 - point.y) * height
        }

        // Clamp within bounds to avoid invalid view origins
        if !x.isFinite || !y.isFinite {
            return CGPoint(x: 0, y: 0)
        }
        x = min(max(x, 0), width)
        y = min(max(y, 0), height)

        return CGPoint(x: x, y: y)
    }
}


extension View {
    @ViewBuilder
    func onValueChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (_ newValue: Value) -> Void
    ) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}
