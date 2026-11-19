# context-threshold-notify

A Claude Code plugin for macOS. It posts a notification when a session's context passes a threshold (default **50% of the context window**), and again after the context drops and climbs back. Clicking the notification brings that session's terminal tab to the front.

## Install

```sh
brew install terminal-notifier          # makes the notification clickable
claude plugin marketplace add asaphe/context-threshold-notify
claude plugin install context-threshold-notify@context-threshold-notify
```

Without `terminal-notifier` you still get a notification, but macOS attributes it to Script Editor, so clicking it opens Script Editor.

The first click may make macOS ask whether `terminal-notifier` may control iTerm2 or Terminal; allow it to get exact-tab focus.

On other operating systems the hooks exit at once and do nothing.

## What a click does

| Terminal | Click result |
|---|---|
| iTerm2 | The exact tab |
| Terminal.app | The exact tab |
| Anything else (Ghostty, VS Code, Cursor, Warp, kitty, WezTerm, …) | The terminal app comes to the front |

## Configure

By default the plugin notifies at **50% of the context window**. A hook can't see the window size, so tell the plugin yours:

```sh
claude plugin configure context-threshold-notify
```

| Option | Default | Meaning |
|---|---|---|
| `window_tokens` | guessed | Your context window in tokens, e.g. `200000` or `1000000`. Left empty, it is guessed: a model name containing `[1m]` (such as `opus[1m]`) means 1,000,000, anything else 200,000. The name comes from the transcript's `requestedModel` when that contains `[1m]` (so `/model` and `--model` are followed), else from `ANTHROPIC_MODEL`, the project's `.claude/settings.local.json` and `.claude/settings.json`, then your user `settings.json`. A context above 200,000 tokens always means a 1,000,000 window |
| `percent` | `50` | Notify at this percent of the window (1–100, no leading zero) |
| `threshold_tokens` | empty | An absolute token threshold; overrides `window_tokens` and `percent` |

Each option can also be set through an environment variable, which wins over the option: `CONTEXT_THRESHOLD_NOTIFY_WINDOW`, `CONTEXT_THRESHOLD_NOTIFY_PERCENT`, `CONTEXT_THRESHOLD_NOTIFY_TOKENS`. Two more are environment-only:

| Environment variable | Default | Meaning |
|---|---|---|
| `CONTEXT_THRESHOLD_NOTIFY_STATE` | `~/.local/state/context-threshold-notify` | Where the per-session markers are kept |
| `CONTEXT_THRESHOLD_NOTIFY_NOTIFIER` | `terminal-notifier` on `PATH` or in Homebrew | Notifier binary |

Set environment variables in the `env` block of `~/.claude/settings.json` so the hooks see them.

## How it works

Hooks on `PostToolUse` and `Stop` read the session's transcript. They take the last main-thread assistant message and add up its `input_tokens`, `cache_read_input_tokens` and `cache_creation_input_tokens`, which is the context that message was sent with. Sub-agent (sidechain) messages are ignored. The hooks never block Claude and always exit 0. If the window was guessed as 200k but is really 1M, you get two notifications: one at 50% of 200k, and another at 50% of 1M, because passing 200k tokens corrects the guess and re-arms the hook. Set `window_tokens` to avoid it. Every call reads the tail of the transcript (the last 256 KiB, or 4 MiB when the last assistant message is longer), including after a notification, because that is how it sees the context drop that re-arms it.

Each session notifies once per climb: when context falls below 80% of the threshold (for example after `/compact`), the hook re-arms and notifies again the next time it passes the threshold. The only state is one empty marker file per session that is currently past the threshold.

Requires `sh`, `sed`, `grep` and `tail`. It uses `jq` when available and falls back to `sed` parsing otherwise.

## Test

```sh
sh tests/run.sh
shellcheck -s sh -S warning scripts/*.sh tests/run.sh
```

CI runs the tests on macOS and Linux, shellcheck on Linux, and a Gitleaks secret scan, for pull requests and pushes to `main`; pull requests also get a DCO sign-off check. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

MIT
