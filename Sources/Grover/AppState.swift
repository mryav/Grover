import Foundation
import Observation

enum Mode {
    /// Just the search bar.
    case compact
    /// Google results with the search bar underneath.
    case expanded
    /// Google results plus one result page on the side.
    case split
}

@Observable
@MainActor
final class AppState {
    var mode: Mode = .compact
    var query = ""
    var isListening = false
    /// Bumped whenever the search field should take focus.
    var focusRequest = 0

    private(set) var history: [String] = UserDefaults.standard.stringArray(forKey: historyKey) ?? []

    private static let historyKey = "history"
    private static let historyLimit = 20

    func remember(_ query: String) {
        history.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        history.insert(query, at: 0)
        history = Array(history.prefix(Self.historyLimit))
        UserDefaults.standard.set(history, forKey: Self.historyKey)
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }
}
