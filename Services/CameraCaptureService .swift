//
//  CameraView.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/17/25.
//

import SwiftUI
import AVFoundation

struct CameraContainerView: View {
    @Binding var videoURL: URL? // Binding to the parent SessionManager's videoURL
    @Binding var isConfirming: Bool

    var body: some View {
        if let url = videoURL {
            PoseVideoOverlayView(videoURL: url)
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                CameraView { url in
                    videoURL = url
                    isConfirming = true
                    // Transition back to main tab interface can be handled here if needed
                }
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                .background(Color.black)
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
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }

        private func setupSession() {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .high

            // Camera input
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: backCamera),
                  captureSession.canAddInput(videoInput) else {
                print("Cannot access back camera")
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
//            recordButton.setTitle("Record", for: .normal)
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
