# Codex Voice Hook

A small macOS Codex CLI hook that queues and speaks short `VOICE:` summaries at the end of turns. It uses the built-in `/usr/bin/say` command, announces the Git project root name (so subfolders share the same label), and also speaks clear decision questions when a marker is missing. Outside a Git repository, it looks for common project files and falls back to the current folder.

## Requirements

- macOS (for `/usr/bin/say`)
- Codex with support for `PermissionRequest` and `Stop` hooks
- Python 3

## Install

Run the installer from this repository:

```sh
./install.sh
```

The installer links the scripts into `~/.codex/hooks/` and registers the `PermissionRequest` event in `~/.codex/hooks.json`. Existing hook configuration is backed up before it is changed. This announces approval requests as they happen while leaving Codex's normal approval prompt in place.

For completed-response speech, add a `Stop` hook to your Codex hook configuration if you do not already use the `turn-ended` notification. For `~/.codex/config.toml`:

```toml
[hooks]
Stop = [{ hooks = [{ type = "command", command = "/usr/bin/python3 /Users/YOUR_NAME/.codex/hooks/speak-notify.py" }] }]
```

Replace `YOUR_NAME` with your macOS account's short name. Restart Codex after changing the configuration.

`PermissionRequest` speaks the project name and a short human-readable request description when Codex is about to show a tool approval prompt. If that optional description is missing or looks like code, it falls back to “Decision needed.” The hook makes no approval decision, so Codex still shows its normal prompt. `Stop` speaks a `VOICE:` marker or a clear decision question in the completed response.

## Ask Codex for spoken summaries

Add a short instruction to `~/.codex/AGENTS.md`:

```markdown
For Codex CLI responses in macOS Terminal, include a final single-line `🗣️ VOICE: ...` marker only when meaningful work is complete, a significant problem occurs, a decision is needed, or the user explicitly asks for speech. When a decision is needed, repeat the exact decision question and options verbatim in the marker so the user hears the choice Codex is waiting on. Keep it plain language; do not put code, file paths, or terminal logs in the marker. Omit the marker for all other responses.
```

The hook speaks a single-line marker outside fenced code blocks. If no valid marker is present, it looks for an explicit choice question or request and speaks that paragraph, including its options. Permission prompts use the separate `PermissionRequest` lifecycle event and announce its optional plain-language description, falling back to “Decision needed.” It rejects code-like punctuation, underscores, and common source or config file names. Keep spoken summaries brief; the hook does not enforce a word limit. Summaries from multiple terminals are queued and played one at a time.

## Stop playback

Run to stop current playback and clear queued summaries:

```sh
~/.codex/hooks/stop-speech
```

## Adjust speech rate

The default is 210 words per minute. Edit the `-r` value in `speak-notify.py` to change it.

## License

MIT. See [LICENSE](LICENSE).
