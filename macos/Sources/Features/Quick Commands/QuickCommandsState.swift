import SwiftUI
import Combine

/// Shared state for Quick Commands sidebar across all windows and tabs.
/// Ensures that sidebar visibility, width, filter, and active group
/// are globally unified and target the currently active terminal session.
@MainActor
final class QuickCommandsState: ObservableObject {
    static let shared = QuickCommandsState()

    private let userDefaults = UserDefaults.standard
    private let isShowingKey = "com.mitchellh.ghostty.quickCommandsIsShowing"
    private let widthKey = "com.mitchellh.ghostty.quickCommandsWidth"

    @Published var isShowing: Bool {
        didSet {
            userDefaults.set(isShowing, forKey: isShowingKey)
        }
    }

    @Published var width: CGFloat {
        didSet {
            userDefaults.set(width, forKey: widthKey)
        }
    }

    @Published var searchText: String = ""
    @Published var selectedGroup: String? = nil
    @Published var isBroadcast: Bool = false
    @Published var selectedIndex: Int? = nil

    private init() {
        self.isShowing = userDefaults.bool(forKey: isShowingKey)
        let savedWidth = CGFloat(userDefaults.double(forKey: widthKey))
        self.width = savedWidth > 150 ? savedWidth : 300
    }

    func toggle() {
        isShowing.toggle()
    }
}
