# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 0.6.x   | ✅ Yes    |
| < 0.6   | ❌ No     |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

To report a vulnerability, please use GitHub's private vulnerability reporting:
**[Report a vulnerability](https://github.com/pimlabs/brewmaster/security/advisories/new)**

Include in your report:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You can expect an acknowledgement within 72 hours and a status update within 7 days.

## Scope

brewmaster is a CLI tool that reads from and writes to:
- `~/.config/brewmaster/` — configuration and profiles
- `~/.local/share/brewmaster/` — audit log and snapshots
- Homebrew's package database (read-only for most operations)

It does not make network requests, does not require elevated privileges, and does not modify system files outside the above paths.