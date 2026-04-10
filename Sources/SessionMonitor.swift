import Foundation
import Combine
import UserNotifications
import AppKit

class SessionMonitor: ObservableObject {
    @Published var sessions: [ClaudeSession] = []
    @Published var lastRefresh: Date = Date()
    @Published var isRefreshing: Bool = false

    private var timer: Timer?
    private let claudeDir: URL
    private let fm = FileManager.default

    // All mutable state guarded by this lock (P1: thread safety)
    private let lock = NSLock()
    private var finishedSessions: [ClaudeSession] = []
    private var notifiedSessionIds: [String: Date] = [:]
    private var jsonlModCache: [String: Date] = [:]
    private var isScanning = false // P1: reentrancy guard

    // UUID regex for session ID validation (P1: path traversal)
    private static let uuidPattern = try! NSRegularExpression(
        pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    )
    // TTY validation (P0: AppleScript injection)
    private static let ttyPattern = try! NSRegularExpression(
        pattern: "^/dev/ttys[0-9]+$"
    )

    var needsAttentionCount: Int { sessions.filter { $0.status == .needsAttention }.count }
    var workingCount: Int { sessions.filter { $0.status == .working }.count }
    var finishedCount: Int { sessions.filter { $0.status == .finished || $0.status == .idle }.count }
    var crashedCount: Int { sessions.filter { $0.status == .crashed }.count }

    var groupedSessions: [(status: SessionStatus, sessions: [ClaudeSession])] {
        let groups = Dictionary(grouping: sessions) { $0.status }
        return SessionStatus.allCases.compactMap { status in
            guard let s = groups[status], !s.isEmpty else { return nil }
            return (status: status, sessions: s)
        }
    }

    init() {
        claudeDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        startMonitoring()
    }

    deinit {
        timer?.invalidate() // P1: timer leak
    }

    func startMonitoring() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        // P1: reentrancy guard — skip if already scanning
        lock.lock()
        if isScanning { lock.unlock(); return }
        isScanning = true
        lock.unlock()

        DispatchQueue.main.async { self.isRefreshing = true }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let scanned = self.scanSessions()

            DispatchQueue.main.async {
                let currentIds = Set(scanned.map(\.id))

                self.lock.lock()
                let newlyFinished = self.sessions.filter {
                    $0.status != .finished && $0.status != .idle && !currentIds.contains($0.id)
                }.map { s -> ClaudeSession in
                    var copy = s
                    copy.status = s.isAlive ? .idle : .finished
                    copy.isAlive = false
                    return copy
                }
                self.finishedSessions = (self.finishedSessions + newlyFinished)
                    .filter { $0.lastActivity.timeIntervalSinceNow > -1800 }
                let finished = self.finishedSessions
                self.lock.unlock()

                let old = Dictionary(self.sessions.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
                self.sessions = scanned + finished
                self.lastRefresh = Date()

                // Notify on state transitions to needsAttention
                for s in scanned where s.status == .needsAttention {
                    let wasAttention = old[s.id] == .needsAttention
                    self.lock.lock()
                    let lastNotified = self.notifiedSessionIds[s.id]
                    self.lock.unlock()
                    let shouldRenotify = lastNotified.map { -$0.timeIntervalSinceNow > 300 } ?? true
                    if !wasAttention || shouldRenotify {
                        self.sendNotification(session: s)
                        self.lock.lock()
                        self.notifiedSessionIds[s.id] = Date()
                        self.lock.unlock()
                    }
                }

                self.isRefreshing = false

                self.lock.lock()
                self.isScanning = false
                self.lock.unlock()
            }
        }
    }

    // MARK: - Scanning

    private func scanSessions() -> [ClaudeSession] {
        let sessionsDir = claudeDir.appendingPathComponent("sessions")
        guard let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)
        else { return [] }

        var results: [ClaudeSession] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = json["pid"] as? Int,
                  let sessionId = json["sessionId"] as? String,
                  let cwd = json["cwd"] as? String,
                  let startMs = json["startedAt"] as? Double else { continue }

            // P1: validate session ID is a UUID (path traversal prevention)
            guard Self.isValidUUID(sessionId) else { continue }

            let isAlive = kill(Int32(pid), 0) == 0
            let startedAt = Date(timeIntervalSince1970: startMs / 1000)
            var status: SessionStatus = isAlive ? .working : .crashed
            var summary = isAlive ? "Starting up..." : "Process exited"
            var lastActivity = startedAt
            var toolAction = ""

            if let jsonlUrl = findJsonl(sessionId: sessionId) {
                let modDate = fileModDate(jsonlUrl) ?? startedAt
                lastActivity = modDate

                // Smart cache: only re-parse if file changed
                lock.lock()
                let cached = jsonlModCache[sessionId]
                lock.unlock()
                let needsParse = cached == nil || cached != modDate

                if needsParse, let info = parseJsonl(at: jsonlUrl) {
                    summary = info.summary
                    toolAction = info.toolAction
                    lock.lock()
                    jsonlModCache[sessionId] = modDate
                    lock.unlock()

                    if isAlive {
                        let staleness = -modDate.timeIntervalSinceNow
                        if staleness < 30 {
                            status = .working
                        } else if staleness < 180 && info.lastType == "assistant" {
                            status = .needsAttention
                        } else if staleness > 300 {
                            status = .stale
                        } else if info.lastType == "assistant" {
                            status = .needsAttention
                        }
                    } else {
                        status = info.lastType == "assistant" ? .finished : .crashed
                    }
                } else if cached != nil {
                    // Use cached state from existing session
                    if let existing = sessions.first(where: { $0.id == sessionId }) {
                        summary = existing.lastSummary
                        toolAction = existing.lastToolAction
                        status = existing.status
                    }
                }
            }

            results.append(ClaudeSession(
                id: sessionId, pid: pid, cwd: cwd, startedAt: startedAt,
                status: status, projectName: extractName(cwd),
                lastSummary: summary, lastActivity: lastActivity,
                isAlive: isAlive, lastToolAction: toolAction
            ))
        }
        return results.sorted {
            $0.status.sortPriority != $1.status.sortPriority
                ? $0.status.sortPriority < $1.status.sortPriority
                : $0.lastActivity > $1.lastActivity
        }
    }

    // MARK: - JSONL Parsing

    private struct ParsedInfo {
        let summary: String
        let toolAction: String
        let lastType: String
    }

    private func parseJsonl(at url: URL) -> ParsedInfo? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let size = fh.seekToEndOfFile()
        if size == 0 { return nil }
        let readSize = min(size, 32768)
        fh.seek(toFileOffset: size - readSize)
        guard let data = try? fh.readToEnd(),
              let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        var summary = ""
        var toolAction = ""
        var lastType = ""

        for line in lines.reversed() {
            // P1: skip potentially split first line from partial UTF-8 read
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = d["type"] as? String else { continue }
            if type == "file-history-snapshot" || type == "last-prompt" || type == "system" { continue }

            if lastType.isEmpty { lastType = type }

            if type == "assistant" && summary.isEmpty {
                if let msg = d["message"] as? [String: Any], let c = msg["content"] {
                    if let arr = c as? [[String: Any]] {
                        for block in arr {
                            let bt = block["type"] as? String ?? ""
                            if bt == "text", let t = block["text"] as? String, !t.isEmpty, summary.isEmpty {
                                summary = cleanText(t)
                            }
                            if bt == "tool_use", toolAction.isEmpty {
                                toolAction = formatTool(block["name"] as? String ?? "", input: block["input"] as? [String: Any] ?? [:])
                            }
                        }
                    } else if let t = c as? String {
                        summary = cleanText(t)
                    }
                }
                if !summary.isEmpty { break }
            } else if type == "progress" {
                if let pd = d["data"] as? [String: Any], pd["type"] as? String == "tool_use_begin" {
                    if toolAction.isEmpty { toolAction = "Using \(pd["toolName"] as? String ?? "tool")..." }
                }
                break
            } else if type == "user" {
                break
            }
        }

        if summary.isEmpty {
            summary = lastType == "progress" ? "Processing..." : "Session active"
        }
        return ParsedInfo(summary: summary, toolAction: toolAction, lastType: lastType)
    }

    // MARK: - Helpers

    private func findJsonl(sessionId: String) -> URL? {
        let dir = claudeDir.appendingPathComponent("projects")
        guard let dirs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for d in dirs {
            let f = d.appendingPathComponent("\(sessionId).jsonl")
            // P1: verify resolved path stays within ~/.claude/projects/
            let resolved = f.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(dir.resolvingSymlinksInPath().path) else { continue }
            if fm.fileExists(atPath: f.path) { return f }
        }
        return nil
    }

    private func fileModDate(_ url: URL) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func formatTool(_ name: String, input: [String: Any]) -> String {
        switch name {
        case "Read":  return "Reading \(URL(fileURLWithPath: input["file_path"] as? String ?? "").lastPathComponent)"
        case "Edit":  return "Editing \(URL(fileURLWithPath: input["file_path"] as? String ?? "").lastPathComponent)"
        case "Write": return "Writing \(URL(fileURLWithPath: input["file_path"] as? String ?? "").lastPathComponent)"
        case "Bash":  return "$ \(String((input["command"] as? String ?? "").prefix(50)))"
        case "Grep":  return "Searching: \(input["pattern"] as? String ?? "")"
        case "Glob":  return "Finding: \(input["pattern"] as? String ?? "")"
        case "Agent": return "Spawning subagent"
        default:      return name
        }
    }

    private func cleanText(_ text: String) -> String {
        let line = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("```") && !$0.hasPrefix("---") && !$0.hasPrefix("|") && !$0.hasPrefix("<") && !$0.hasPrefix("*") }
        let s = line ?? String(text.prefix(120))
        return s.count > 120 ? String(s.prefix(120)) + "..." : s
    }

    private func extractName(_ cwd: String) -> String {
        String(cwd.split(separator: "/").last ?? "Unknown")
    }

    // P1: UUID validation
    private static func isValidUUID(_ s: String) -> Bool {
        uuidPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // P0: TTY path validation (prevents AppleScript injection)
    static func isValidTTY(_ path: String) -> Bool {
        ttyPattern.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    // MARK: - Notifications

    private func sendNotification(session: ClaudeSession) {
        let content = UNMutableNotificationContent()
        content.title = "\(session.projectName) needs you"
        content.body = session.lastSummary
        content.sound = .default
        content.categoryIdentifier = "SESSION_ATTENTION"

        let req = UNNotificationRequest(
            identifier: "attention-\(session.id)",
            content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Dispatch

    func dispatch(to session: ClaudeSession, message: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 1. Get and validate TTY (P0: AppleScript injection prevention)
            let tty = self.getTTY(pid: session.pid)
            guard !tty.isEmpty else { return }
            let device = "/dev/" + tty
            guard Self.isValidTTY(device) else { return }

            // P1: verify the PID still belongs to a claude process
            guard self.verifyProcess(pid: session.pid) else { return }

            // 2. Copy message to clipboard (P0: no DispatchQueue.main.sync — use async)
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
            }

            // Small delay to ensure clipboard is set
            Thread.sleep(forTimeInterval: 0.1)

            // 3. Focus terminal + paste + Enter
            let isIterm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
            let termApp = isIterm ? "iTerm2" : "Terminal"

            let script: String
            if isIterm {
                script = """
                tell application "iTerm2"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is "\(device)" then
                                    select t
                                    tell w to select
                                    activate
                                    delay 0.3
                                    tell application "System Events"
                                        tell process "\(termApp)"
                                            keystroke "v" using command down
                                            delay 0.15
                                            key code 36
                                        end tell
                                    end tell
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                """
            } else {
                script = """
                tell application "Terminal"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "\(device)" then
                                set selected tab of w to t
                                set index of w to 1
                                activate
                                delay 0.3
                                tell application "System Events"
                                    tell process "\(termApp)"
                                        keystroke "v" using command down
                                        delay 0.15
                                        key code 36
                                    end tell
                                end tell
                                return
                            end if
                        end repeat
                    end repeat
                end tell
                """
            }

            self.runOsascript(script)

            // P1: clear clipboard after dispatch (1 second delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSPasteboard.general.clearContents()
            }
        }
    }

    private func getTTY(pid: Int) -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-p", "\(pid)", "-o", "tty="]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        return (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // P1: verify PID belongs to a claude/node process before dispatch
    private func verifyProcess(pid: Int) -> Bool {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-p", "\(pid)", "-o", "comm="]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        let comm = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let basename = (comm as NSString).lastPathComponent
        return basename == "claude" || basename == "node"
    }

    private func runOsascript(_ script: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }
}
