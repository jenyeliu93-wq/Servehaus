import SwiftUI
import Combine

@MainActor
class SessionManager: ObservableObject {
    @Published var videoURL: URL?
    @Published var result: SessionGradingResult?
    @Published var isAnalyzing: Bool = false
}

struct MainTabContainerView: View {
    @StateObject private var sessionManager = SessionManager()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // 1️⃣ VIDEO TAB
            // 1️⃣ VIDEO TAB
            UploadOrRecordView(sessionManager: sessionManager)
                .tabItem {
                    Label("Video", systemImage: "video")
                }
                .tag(0)

            // 2️⃣ OVERLAY TAB
            Group {
                if sessionManager.isAnalyzing {
                    ProgressView("Analyzing...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let url = sessionManager.videoURL {
                    PoseVideoOverlayView(videoURL: url)
                } else {
                    Text("Upload or record a video to view overlay.")
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("Overlay", systemImage: "figure.tennis")
            }
            .tag(1)

            // 3️⃣ DASHBOARD TAB
            Group {
                if let result = sessionManager.result {
                    GradingReportTabView(result: result)
                } else {
                    Text("No analysis results yet. Please upload or record a video.")
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.fill")
            }
            .tag(2)
        }
    }
}

@main
struct ServiceHausAI_testApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabContainerView()
        }
    }
}
