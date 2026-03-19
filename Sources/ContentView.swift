import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SessionMonitor
    @State private var pinned = false
    @State private var searchText = ""

    var filteredGroups: [(status: SessionStatus, sessions: [ClaudeSession])] {
        if searchText.isEmpty { return monitor.groupedSessions }
        return monitor.groupedSessions.compactMap { g in
            let f = g.sessions.filter {
                $0.projectName.localizedCaseInsensitiveContains(searchText) ||
                $0.lastSummary.localizedCaseInsensitiveContains(searchText)
            }
            return f.isEmpty ? nil : (status: g.status, sessions: f)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            stats
            Divider()
            if monitor.sessions.count > 3 { search }
            content
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("ClaudeWatch")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: { monitor.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .rotationEffect(.degrees(monitor.isRefreshing ? 360 : 0))
                    .animation(monitor.isRefreshing ? .linear(duration: 0.5).repeatForever(autoreverses: false) : .default, value: monitor.isRefreshing)
            }
            .buttonStyle(.borderless)
            Button(action: { togglePin() }) {
                Image(systemName: pinned ? "pin.fill" : "pin.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(pinned ? Color(nsColor: .systemOrange) : .secondary)
            }
            .buttonStyle(.borderless)
            .help(pinned ? "Unpin" : "Keep on top")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Stats

    private var stats: some View {
        HStack(spacing: 0) {
            if monitor.needsAttentionCount > 0 {
                Stat(n: monitor.needsAttentionCount, label: "waiting", color: Color(nsColor: .systemOrange))
            }
            Stat(n: monitor.workingCount, label: "active", color: Color(nsColor: .systemGreen))
            Stat(n: monitor.finishedCount, label: "done", color: Color(nsColor: .systemGray))
            if monitor.crashedCount > 0 {
                Stat(n: monitor.crashedCount, label: "crashed", color: Color(nsColor: .systemRed))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Search

    private var search: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(.tertiary)
            TextField("Filter...", text: $searchText).textFieldStyle(.plain).font(.system(size: 11))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(6)
        .padding(.horizontal, 14).padding(.vertical, 4)
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if monitor.sessions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("No active sessions")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Launch Claude Code in a terminal to start")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredGroups, id: \.status) { group in
                            GroupHeader(status: group.status, count: group.sessions.count)
                            ForEach(group.sessions) { session in
                                SessionRowView(session: session, monitor: monitor)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Circle().fill(Color(nsColor: .systemGreen)).frame(width: 5, height: 5)
            Text("Live")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(monitor.sessions.count) sessions")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func togglePin() {
        pinned.toggle()
        NSApplication.shared.windows
            .first { $0.title.contains("ClaudeWatch") }?
            .level = pinned ? .floating : .normal
    }
}

// MARK: - Supporting Views

struct Stat: View {
    let n: Int; let label: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text("\(n)").font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(n > 0 ? color : Color.gray.opacity(0.4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GroupHeader: View {
    let status: SessionStatus; let count: Int
    var body: some View {
        HStack(spacing: 5) {
            Text(status.groupLabel)
                .font(.system(size: 10, weight: .bold)).tracking(0.5)
                .foregroundStyle(status.color)
            Text("(\(count))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4).padding(.top, 10).padding(.bottom, 3)
    }
}
