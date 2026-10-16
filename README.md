# Codex Voice Hook

A small macOS Codex CLI hook that queues and speaks short `VOICE:` summaries at the end of turns. It uses the built-in `/usr/bin/say` command, announces the Git project root name (so subfolders share the same label), and stays silent when the response has no valid marker. Outside a Git repository, it looks for common project files and falls back to the current folder.

## Requirements

- macOS (for `/usr/bin/say`)
- Codex CLI with support for `Stop` hooks
- Python 3

## Install

Copy `speak-notify.py` and `stop-speech` into `~/.codex/hooks/`, then make the stop command executable:

```sh
mkdir -p ~/.codex/hooks
cp speak-notify.py stop-speech ~/.codex/hooks/
chmod +x ~/.codex/hooks/stop-speech
```

Add this hook to `~/.codex/config.toml`, merging it with any existing `hooks` section:

```toml
[hooks]
Stop = [{ command = "/usr/bin/python3", args = ["/Users/YOUR_NAME/.codex/hooks/speak-notify.py"] }]
```

Replace `YOUR_NAME` with your macOS account's short name. Restart Codex after changing the configuration.

If you use another hook for `Stop`, add this command to that hook list instead of replacing it.

### Link the installed hook to this checkout

Run `./install.sh` from this repository. It links the speech and stop scripts into your Codex hooks directory and saves any files it replaces as timestamped backups. If your Codex config already points to `~/.codex/hooks/speak-notify.py`, no config change is needed. Changes pulled into this checkout take effect immediately through the links. Run `./update.sh` to pull the latest GitHub version and refresh the links. GitHub changes are not downloaded automatically.

## Ask Codex for spoken summaries

Add a short instruction to `~/.codex/AGENTS.md`:

```markdown
For Codex CLI responses in macOS Terminal, include a final single-line `VOICE: ...` marker only when meaningful work is complete, a significant problem occurs, a decision is needed, or the user explicitly asks for speech. Keep it plain language; do not put code, file paths, or terminal logs in the marker. Omit the marker for all other responses.
```

The hook speaks only a single-line marker outside fenced code blocks. It rejects code-like punctuation, underscores, and common source or config file names. Keep spoken summaries brief; the hook does not enforce a word limit. Summaries from multiple terminals are queued and played one at a time.

## Stop playback

Run to stop current playback and clear queued summaries:

```sh
~/.codex/hooks/stop-speech
```

## Adjust speech rate

The default is 210 words per minute. Edit the `-r` value in `speak-notify.py` to change it.

## License

MIT. See [LICENSE](LICENSE).
