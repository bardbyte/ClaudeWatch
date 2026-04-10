# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 1.x     | Yes                |

## Reporting a Vulnerability

If you discover a security vulnerability in ClaudeWatch, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email **security@bardbyte.com** with:

1. A description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

You should receive an acknowledgment within 48 hours. We aim to release a fix within 7 days for critical issues.

## Threat Model

ClaudeWatch is a **local-only macOS desktop application**. It has:

- **No network access** -- all data stays on your machine
- **No external dependencies** -- system frameworks only
- **No data collection or telemetry**
- **Read-only filesystem access** to `~/.claude/` for session monitoring

### Attack surface

| Vector | Mitigation |
|--------|-----------|
| AppleScript injection via TTY path | Strict regex validation: `/dev/ttys[0-9]+` |
| Path traversal via session ID | UUID format validation + symlink resolution with directory containment check |
| Dispatch to wrong process | PID ownership verified (must be `claude` or `node` process) |
| Clipboard leakage | Clipboard cleared 1.5s after dispatch |
| Arbitrary key simulation | Wispr Flow key codes bounded to 0-127 |

### Permissions required

- **Accessibility**: Terminal window focusing and keyboard dispatch
- **Notifications**: Alert when a session needs attention

## Security Design Principles

1. **Validate all interpolated strings** before AppleScript execution
2. **Resolve symlinks** and verify path containment before file reads
3. **Verify process ownership** before dispatching to any PID
4. **Clear sensitive clipboard data** after use
5. **Use argument arrays** (not shell strings) for process execution
