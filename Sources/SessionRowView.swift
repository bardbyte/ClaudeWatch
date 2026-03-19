import SwiftUI

struct SessionRowView: View {
    let session: ClaudeSession
    @ObservedObject var monitor: SessionMonitor
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var showDispatch = false
    @State private var dispatchText = ""
    @State private var isVoiceActive = false
    @FocusState private var dispatchFocused: Bool

    private var isWisprFlowRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.electron.wispr-flow" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if isExpanded { detailSection }
            if showDispatch { dispatchSection }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { isHovered = h } }
        .padding(.vertical, 1)
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status dot with pulse for working
            ZStack {
                if session.status == .working {
                    Circle().fill(session.status.color.opacity(0.15)).frame(width: 16, height: 16)
                }
                Circle().fill(session.status.color).frame(width: 8, height: 8)
            }
            .frame(width: 16, height: 16)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    if session.status == .needsAttention && !showDispatch {
                        // Voice-first: Tap In auto-activates Wispr Flow if running
                        Button(action: { openDispatch(autoVoice: isWisprFlowRunning) }) {
                            HStack(spacing: 3) {
                                if isWisprFlowRunning {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 7))
                                }
                                Text("Tap In")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(nsColor: .systemOrange)))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(session.elapsedTime)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(session.lastSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(isExpanded ? 4 : 1)

                HStack(spacing: 0) {
                    if !session.lastToolAction.isEmpty {
                        Text(session.lastToolAction)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isHovered && session.isAlive {
                        HStack(spacing: 2) {
                            MiniBtn(icon: "terminal.fill", tip: "Focus terminal") { focusTerminal() }
                            MiniBtn(icon: "folder", tip: "Reveal in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
                            }
                            MiniBtn(icon: "doc.on.doc", tip: "Copy path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(session.cwd, forType: .string)
                            }
                            if !showDispatch {
                                MiniBtn(icon: "paperplane", tip: "Dispatch task") { openDispatch() }
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    // MARK: - Dispatch (Tap In)

    private func openDispatch(autoVoice: Bool = false) {
        withAnimation(.easeOut(duration: 0.15)) {
            showDispatch = true
            isExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            dispatchFocused = true
            if autoVoice {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    triggerWisprFlow()
                }
            }
        }
    }

    private func triggerWisprFlow() {
        // Read Wispr Flow's activation key from its config
        // Default: Fn key (keyCode 63) for push-to-talk
        let wisprKeyCode = readWisprActivationKey()

        let script = """
        tell application "System Events"
            key code \(wisprKeyCode)
        end tell
        """
        runOsascript(script)
        isVoiceActive = true
    }

    private func readWisprActivationKey() -> Int {
        // Read from Wispr Flow config to find the PTT key
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wispr Flow/config.json")
        if let data = try? Data(contentsOf: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let prefs = json["prefs"] as? [String: Any],
           let user = prefs["user"] as? [String: Any],
           let shortcuts = user["shortcuts"] as? [String: String] {
            for (key, value) in shortcuts where value == "ptt" {
                // P0: bound key code to valid range (0-127) to prevent arbitrary key simulation
                if let code = Int(key), code >= 0, code <= 127 { return code }
            }
        }
        return 63 // Default: Fn key
    }

    private var dispatchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)

            HStack {
                Text("DISPATCH TASK")
                    .font(.system(size: 8, weight: .bold)).tracking(0.5)
                    .foregroundStyle(.tertiary)
                Spacer()
                if isWisprFlowRunning {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(isVoiceActive ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                            .frame(width: 5, height: 5)
                        Text(isVoiceActive ? "Listening..." : "Wispr Flow ready")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(isVoiceActive ? Color(nsColor: .systemGreen) : Color.gray)
                    }
                }
            }

            // Voice button row
            if isWisprFlowRunning {
                HStack(spacing: 6) {
                    Button(action: { triggerWisprFlow() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isVoiceActive ? "waveform" : "mic.fill")
                                .font(.system(size: 10))
                            Text(isVoiceActive ? "Dictating..." : "Start Voice")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                isVoiceActive
                                    ? Color(nsColor: .systemGreen).opacity(0.15)
                                    : Color(nsColor: .systemOrange).opacity(0.1)
                            )
                        )
                        .foregroundStyle(isVoiceActive ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                    }
                    .buttonStyle(.plain)

                    Text("or type below")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            TextEditor(text: $dispatchText)
                .font(.system(size: 11))
                .frame(minHeight: 48, maxHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    isVoiceActive
                                        ? Color(nsColor: .systemGreen).opacity(0.4)
                                        : Color(nsColor: .systemOrange).opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                )
                .focused($dispatchFocused)
                .overlay(alignment: .topLeading) {
                    if dispatchText.isEmpty {
                        Text(isVoiceActive ? "Speak now..." : "Type a task or click Start Voice...")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: dispatchText) { _, _ in
                    // When text appears (from Wispr Flow or typing), mark voice as done
                    if isVoiceActive && !dispatchText.isEmpty {
                        isVoiceActive = false
                    }
                }

            HStack {
                Text("Cmd+Return to send")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Cancel") {
                    withAnimation { showDispatch = false; dispatchText = ""; isVoiceActive = false }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                Button(action: { sendDispatch() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 8))
                        Text("Send")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(dispatchText.isEmpty ? Color.gray.opacity(0.3) : Color(nsColor: .systemOrange)))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(dispatchText.isEmpty)
            }
        }
        .padding(.top, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func sendDispatch() {
        guard !dispatchText.isEmpty else { return }
        let msg = dispatchText
        dispatchText = ""
        withAnimation { showDispatch = false }
        monitor.dispatch(to: session, message: msg)
    }

    // MARK: - Detail

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider().padding(.vertical, 4)
            InfoRow(k: "Path", v: session.shortPath)
            InfoRow(k: "PID", v: "\(session.pid)")
            InfoRow(k: "Session", v: String(session.id.prefix(8)))
            InfoRow(k: "Started", v: fmtTime(session.startedAt))
        }
        .padding(.leading, 24)
        .transition(.opacity)
    }

    // MARK: - Terminal Focus

    // P0: run all Process calls off main thread
    private func focusTerminal() {
        DispatchQueue.global(qos: .userInteractive).async {
            let dev = self.getTTYDevice(pid: self.session.pid)
            guard !dev.isEmpty, SessionMonitor.isValidTTY(dev) else { return }
            self.runOsascript(self.focusScript(device: dev))
        }
    }

    private func getTTYDevice(pid: Int) -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-p", "\(pid)", "-o", "tty="]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        let tty = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tty.isEmpty ? "" : "/dev/" + tty
    }

    private func focusScript(device: String) -> String {
        // P0: device is already validated by isValidTTY before reaching here
        let isIterm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
        if isIterm {
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(device)" then
                                select t
                                tell w to select
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        }
        return """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(device)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
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

    // MARK: - Helpers

    private var cardBg: Color {
        session.status == .needsAttention
            ? Color(nsColor: .systemOrange).opacity(isHovered ? 0.10 : 0.05)
            : Color.primary.opacity(isHovered ? 0.06 : 0.03)
    }

    private func fmtTime(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}

// MARK: - Mini Button

struct MiniBtn: View {
    let icon: String; let tip: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help(tip)
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let k: String; let v: String
    var body: some View {
        HStack(spacing: 6) {
            Text(k).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(v).font(.system(size: 10, design: .monospaced)).foregroundStyle(.primary.opacity(0.7))
                .lineLimit(1).textSelection(.enabled)
        }
    }
}
