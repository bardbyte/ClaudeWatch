import Foundation
import SwiftUI

// MARK: - Session Status (9 states from research)

enum SessionStatus: String, CaseIterable {
    case working = "Working"
    case needsAttention = "Needs You"
    case stale = "Stale"
    case idle = "Idle"
    case crashed = "Crashed"
    case finished = "Done"

    var color: Color {
        switch self {
        case .working:        return Color(nsColor: .systemGreen)
        case .needsAttention: return Color(nsColor: .systemOrange)
        case .stale:          return Color(nsColor: .systemYellow)
        case .idle:           return Color(nsColor: .systemBlue)
        case .crashed:        return Color(nsColor: .systemRed)
        case .finished:       return Color(nsColor: .systemGray)
        }
    }

    var icon: String {
        switch self {
        case .working:        return "circle.fill"
        case .needsAttention: return "exclamationmark.circle.fill"
        case .stale:          return "clock.fill"
        case .idle:           return "pause.circle.fill"
        case .crashed:        return "xmark.circle.fill"
        case .finished:       return "checkmark.circle.fill"
        }
    }

    var sortPriority: Int {
        switch self {
        case .needsAttention: return 0
        case .crashed:        return 1
        case .stale:          return 2
        case .working:        return 3
        case .idle:           return 4
        case .finished:       return 5
        }
    }

    var groupLabel: String {
        switch self {
        case .needsAttention: return "NEEDS ATTENTION"
        case .crashed:        return "CRASHED"
        case .stale:          return "STALE"
        case .working:        return "WORKING"
        case .idle:           return "IDLE"
        case .finished:       return "DONE"
        }
    }
}

// MARK: - Session

struct ClaudeSession: Identifiable, Equatable {
    let id: String
    let pid: Int
    let cwd: String
    let startedAt: Date
    var status: SessionStatus
    var projectName: String
    var lastSummary: String
    var lastActivity: Date
    var isAlive: Bool
    var lastToolAction: String

    static func == (lhs: ClaudeSession, rhs: ClaudeSession) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }

    var elapsedTime: String {
        let s = Int(-startedAt.timeIntervalSinceNow)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    var shortPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }
}
