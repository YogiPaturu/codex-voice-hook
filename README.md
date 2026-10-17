# Codex Voice Hook

A small macOS Codex CLI hook that queues and speaks short `VOICE:` summaries at the end of turns. It uses the built-in `/usr/bin/say` command, announces the Git project root name (so subfolders share the same label), and also speaks clear decision questions when a marker is missing. Outside a Git repository, it looks for common project files and falls back to the current folder.

## Quick start

On macOS, clone this repository and run the installer:

```sh
git clone https://github.com/YogiPaturu/codex-voice-hook.git
cd codex-voice-hook
./install.sh
```

The installer links the scripts into `~/.codex/hooks/`, registers approval announcements in `~/.codex/hooks.json`, adds completed-response speech to `~/.codex/config.toml`, and syncs a marked instruction block in `~/.codex/AGENTS.md`. It updates the earlier plain `VOICE:` instruction to require `🗣️ VOICE:` on its own new line, while preserving other instructions and backing up files before changing them. Python 3 is required; macOS includes `/usr/bin/python3` and `/usr/bin/say`.

After the first install, update everything from this checkout with:

```sh
./update.sh
```

This fast-forwards the repository and reinstalls everything: both hook scripts, Codex hook registrations, and the spoken-response instruction. Codex runs the hook scripts when their events occur; you do not need to run them yourself. Restart Codex if it is already running.

## What it speaks

`PermissionRequest` says “Project [terminal project name]. Decision needed.” The project name comes from the terminal's working directory (or the Git root when available), and the hook does not speak the tool description. The `Stop` hook speaks a `VOICE:` marker or a clear decision question from completed responses. If no marker is present, the hook looks for an explicit choice request. It filters code-like text and queues speech from multiple terminals.

## Stop playback

Run to stop current playback and clear queued summaries:

```sh
~/.codex/hooks/stop-speech
```

## Adjust speech rate

The default is 210 words per minute. Edit the `-r` value in `speak-notify.py` to change it.

## License

MIT. See [LICENSE](LICENSE).
