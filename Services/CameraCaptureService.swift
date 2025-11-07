//
//  CameraView.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/17/25.
//

import SwiftUI
import AVFoundation
import AVKit

struct CameraContainerView: View {
    @ObservedObject var sessionManager: SessionManager
    var onRecordingFinished: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CameraView { url in
                onRecordingFinished(url)
                dismiss()
            }
            .edgesIgnoringSafeArea(.all)

            VStack {
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.top, 44)
                .padding(.horizontal)
                Spacer()
            }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    var onRecordingFinished: (URL) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onFinishRecording = onRecordingFinished
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // No-op
    }

    class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
        private let captureSession = AVCaptureSession()
        private let movieOutput = AVCaptureMovieFileOutput()
        private var previewLayer: AVCaptureVideoPreviewLayer!
        private let recordButton = UIButton(type: .system)
        private var isRecording = false

        var onFinishRecording: ((URL) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            setupSession()
            setupPreview()
            setupRecordButton()
        }

        private func setupSession() {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.configureSession()
                } else {
                    print("Camera access denied")
                }
            }
        }

        private func configureSession() {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .high

            // Camera input
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: backCamera),
                  captureSession.canAddInput(videoInput) else {
                print("Cannot access back camera")
                captureSession.commitConfiguration()
                return
            }
            captureSession.addInput(videoInput)

            // Microphone input
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }

            // Movie output
            if captureSession.canAddOutput(movieOutput) {
                captureSession.addOutput(movieOutput)
            }
            captureSession.commitConfiguration()
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }

        private func setupPreview() {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.insertSublayer(previewLayer, at: 0)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer.frame = view.bounds
        }

        private func setupRecordButton() {
            recordButton.translatesAutoresizingMaskIntoConstraints = false
            recordButton.backgroundColor = .red
            recordButton.setTitleColor(.white, for: .normal)
            recordButton.layer.cornerRadius = 32
            recordButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
            recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
            view.addSubview(recordButton)
            NSLayoutConstraint.activate([
                recordButton.widthAnchor.constraint(equalToConstant: 64),
                recordButton.heightAnchor.constraint(equalToConstant: 64),
                recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
                recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            ])
        }

        @objc private func toggleRecording() {
            if isRecording {
                movieOutput.stopRecording()
                recordButton.setTitle("Record", for: .normal)
                recordButton.backgroundColor = .red
            } else {
                guard captureSession.isRunning,
                      movieOutput.connections.contains(where: { $0.isActive }) else {
                    print("Capture session is not ready")
                    return
                }
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                movieOutput.startRecording(to: outputURL, recordingDelegate: self)
                recordButton.setTitle("Stop", for: .normal)
                recordButton.backgroundColor = .gray
            }
            isRecording.toggle()
        }

        // MARK: - AVCaptureFileOutputRecordingDelegate
        func fileOutput(_ output: AVCaptureFileOutput,
                        didFinishRecordingTo outputFileURL: URL,
                        from connections: [AVCaptureConnection],
                        error: Error?) {
            if let error = error {
                print("Recording error: \(error.localizedDescription)")
            } else {
                print("Saved video to: \(outputFileURL)")
                DispatchQueue.main.async {
                    self.onFinishRecording?(outputFileURL)
                }
            }
        }
    }
}
