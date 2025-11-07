import SwiftUI
import Combine

final class SessionManager: ObservableObject {
    enum SessionTab {
        case video
        case overlay
        case report
    }

    enum SessionPhase: Equatable {
        case idle
        case ready
        case analyzing
        case completed
    }

    @Published var videoURL: URL? = nil
    @Published var result: SessionGradingResult? = nil
    @Published var isAnalyzing: Bool = false
    @Published var currentTab: SessionTab = .video
    @Published var phase: SessionPhase = .idle   // ✅ Add this
    @Published var isVideoConfirmed: Bool = false
    @Published var sessionUUID: UUID = UUID()

    func reset() {
        videoURL = nil
        result = nil
        isAnalyzing = false
        currentTab = .video
        phase = .idle                            // ✅ reset to idle
        isVideoConfirmed = false
        PoseVideoOverlayView.analyzedVideos.removeAll()
        sessionUUID = UUID()   // 🔥 add this line
    }
}


@main
struct ServiceHausAI_testApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(sessionManager) // ✅ must be here
        }
    }
}
