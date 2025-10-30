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
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Upload Tennis Session")
                .font(.title2)
                .bold()
            
            if let url = selectedVideoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 280)
                    .cornerRadius(8)
                    .padding()
                
                if isConfirming {
                    HStack(spacing: 20) {
                        Button(action: {
                            isConfirming = false
                            sessionManager.videoURL = url
                            sessionManager.isAnalyzing = true
                            Task {
                                do {
                                    let result = try await StrokeAnalysisPipeline.analyze(
                                        videoURL: url,
                                        progressCallback: { progress in
                                            print("Analysis progress: \(progress)")
                                        }
                                    )
                                    await MainActor.run {
                                        sessionManager.result = result
                                        sessionManager.isAnalyzing = false
                                    }
                                } catch {
                                    print("Analysis failed: \(error)")
                                    await MainActor.run {
                                        sessionManager.isAnalyzing = false
                                    }
                                }
                            }
                        }) {
                            Text("✅ Confirm Video")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
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
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
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
            }
            
            Spacer()
        }
        .padding()
        .onChange(of: selectedItem, initial: false) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mov")
                    try? data.write(to: tempURL)
                    selectedVideoURL = tempURL
                    isConfirming = true
                }
            }
        }
    }
}
