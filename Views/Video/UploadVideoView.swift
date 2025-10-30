//
//  UploadVideoView.swift
//  ServiceHausAI_test
//
//  Created by Ye Liu on 10/20/25.
//

//
//  UploadVideoView.swift
//  ServiceHausAI_test
//

import SwiftUI
import PhotosUI
import AVKit

struct UploadOrRecordView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var isConfirming = false
    @State private var isRecording = false
    @State private var showAlert = false
    @State private var showRestartButton = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 24) {
                Text("Upload Tennis Session")
                    .font(.title2)
                    .bold()
                
                if let url = selectedVideoURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: ((UIApplication.shared.connectedScenes.first as? UIWindowScene)?
                            .screen.bounds.height ?? 600) * 0.36)
                        .cornerRadius(8)
                        .padding()
                    
                    if isConfirming {
                        HStack(spacing: 20) {
//                            Button(action: {
//                                guard let url = selectedVideoURL else { return }
//                                sessionManager.videoURL = url
//                                sessionManager.isAnalyzing = true
//                                sessionManager.phase = .ready
//                                sessionManager.currentTab = .overlay
//                                isConfirming = false
//                            })
                            Button(action: {
                                guard let url = selectedVideoURL else {
                                    print("⚠️ Confirm clicked but no selectedVideoURL found")
                                    return
                                }

                                print("✅ Confirm clicked")
                                print("Before confirm → phase:", sessionManager.phase)

                                sessionManager.videoURL = url
                                sessionManager.phase = .ready
                                sessionManager.currentTab = .overlay

                                print("After confirm → phase:", sessionManager.phase)
                                print("After confirm → videoURL:", sessionManager.videoURL?.absoluteString ?? "nil")
                                print("After confirm → currentTab:", sessionManager.currentTab)

                                isConfirming = false
                            }){
                                Text("✅ Confirm Video")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.green)
                                    .cornerRadius(12)
                            }
                            
                            Button(action: {
                                selectedItem = nil
                                selectedVideoURL = nil
                            }) {
                                Text("🔄 Choose Another")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.red)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                } else {
                    VStack(spacing: 16) {
                        PhotosPicker(
                            selection: $selectedItem,
                            matching: .videos,
                            photoLibrary: .shared()
                        ) {
                            Label("Choose Video", systemImage: "video.fill.badge.plus")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        Button(action: {
                            isRecording = true
                        }) {
                            Label("Record Session", systemImage: "record.circle.fill")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .sheet(isPresented: $isRecording) {
                CameraContainerView(sessionManager: sessionManager)
            }
            .onChange(of: selectedItem, initial: false) { _, newItem in
                print("DEBUG: selectedItem changed to \(String(describing: newItem))")
                Task {
                    if let item = newItem {
                        do {
                            if let data = try await item.loadTransferable(type: Data.self) {
                                let tempURL = FileManager.default.temporaryDirectory
                                    .appendingPathComponent(UUID().uuidString)
                                    .appendingPathExtension("mov")
                                try data.write(to: tempURL)
                                await MainActor.run {
                                    PoseVideoOverlayView.analyzedVideos.removeAll()
                                    selectedVideoURL = tempURL
                                    isConfirming = true
                                }
                                print("DEBUG: ✅ Video loaded and ready for confirm")
                            } else {
                                print("DEBUG: ⚠️ Failed to load video data")
                            }
                        } catch {
                            print("DEBUG: ❌ Error loading video - \(error)")
                        }
                    } else {
                        print("DEBUG: selectedItem is nil")
                    }
                }
            }
            .onChange(of: sessionManager.phase) { _, newPhase in
                if newPhase == .completed && sessionManager.currentTab == .video {
                    showRestartButton = true
                } else {
                    showRestartButton = false
                }
            }
            .onChange(of: sessionManager.currentTab) { _, newTab in
                if newTab == .video && sessionManager.phase == .completed {
                    showRestartButton = true
                } else {
                    showRestartButton = false
                }
            }
            
            if showRestartButton {
                Button {
                    sessionManager.reset()
                    clearLocalState()
                } label: {
                    Label("Start New Session", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .padding(.bottom, 80) // 确保按钮位于 Tab 上方可见
            }
        }
    }
    
    private func clearLocalState() {
        selectedItem = nil
        selectedVideoURL = nil
        isConfirming = false
        isRecording = false
        showAlert = false
    }
}
