# Security policy

## Reporting a vulnerability

Report privately through GitHub Security Advisories:
**[Report a vulnerability](https://github.com/asaphe/context-threshold-notify/security/advisories/new)**

Please do not open a public issue for a security report.

This is a solo-maintained project. Expect an acknowledgement within a week and a
fix or an explicit decision not to fix within a month. There is no paid support
and no SLA.

## Supported versions

Pre-1.0. Only the current `main` is supported.

## What counts as a vulnerability here

The hooks run after every tool call and at every stop, with your user's rights, and the
notification's click runs a shell command. In scope:

- Hook input (a session ID, transcript path or cwd), an environment value or a plugin
  option that reaches the click command, an AppleScript string or a file path unescaped.
- A marker written outside the state directory.
- A click that focuses, or runs anything in, a terminal other than the session's own.

Out of scope:

- A wrong token count or a missed or extra notification. That is a bug; open an issue.
- Findings that require an attacker who can already write to the plugin's scripts,
  your Claude Code settings or the state directory.
