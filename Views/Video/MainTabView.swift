import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        TabView(selection: $sessionManager.currentTab) {
            // 📹 Video
            UploadOrRecordView(sessionManager: sessionManager)
                .tabItem {
                    Label("Video", systemImage: "video.fill")
                }
                .tag(SessionManager.SessionTab.video)
            
            // 🎯 Overlay
            PoseVideoOverlayView(videoURL: sessionManager.videoURL)
                .tabItem {
                    Label("Overlay", systemImage: "figure.walk.motion")
                        .foregroundStyle(sessionManager.videoURL == nil ? .gray : .primary)
                }
                .tag(SessionManager.SessionTab.overlay)
            
            // 📊 Report
            GradingReportTabView()
                .tabItem {
                    Label("Report", systemImage: "chart.bar.fill")
                        .foregroundStyle(sessionManager.result == nil ? .gray : .primary)
                }
                .tag(SessionManager.SessionTab.report)
        }
        .onChange(of: sessionManager.currentTab, initial: false) { oldTab, newTab in
//            // 强制防止切换到被禁用的 tab
//            if newTab == .overlay && sessionManager.videoURL == nil {
//                sessionManager.currentTab = .video
//            }
        }
        .onChange(of: sessionManager.phase) { oldPhase, newPhase in
            // ✅ 当上传视频后状态进入 .ready，自动切换到 Overlay tab 开始分析
            if newPhase == .ready {
                withAnimation {
                    sessionManager.currentTab = .overlay
                }
            }

            // ✅ 分析完成后自动跳转到 Report tab
            if oldPhase == .analyzing && newPhase == .completed {
                withAnimation {
                    sessionManager.currentTab = .report
                }
            }
        }
    }
}
