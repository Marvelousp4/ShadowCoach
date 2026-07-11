# Setup

## Required

- macOS 13 or newer
- Xcode Command Line Tools: `xcode-select --install`

## Recommended Import Tools

```bash
./scripts/install-local-tools.sh --media
```

This uses the repository `Brewfile` to install FFmpeg and yt-dlp from Homebrew. It does not copy third-party binaries into the Git repository.

## Optional Prosody Analysis

Use an isolated Python environment:

```bash
python3 -m venv ~/.local/share/shadowcoach-analysis-venv
~/.local/share/shadowcoach-analysis-venv/bin/pip install praat-parselmouth
export SHADOW_COACH_PYTHON="$HOME/.local/share/shadowcoach-analysis-venv/bin/python"
```

The supported all-in-one local analysis setup is:

```bash
./scripts/install-local-tools.sh --analysis
```

It creates `~/.local/share/shadowcoach-whisperx-venv`, then installs the pinned versions in `requirements/local-analysis.txt`. The App detects this location automatically.

WhisperX currently requires Python 3.10–3.13. The installer automatically uses or installs Homebrew Python 3.11 and will reject an incompatible default such as Python 3.14. Allow roughly 2 GB of free disk space for the environment and first-use models.

## Optional Transcription

Install WhisperX in its own environment and point Shadow Coach to the executable:

```bash
export SHADOW_COACH_WHISPERX_COMMAND="$HOME/.local/share/shadowcoach-whisperx-venv/bin/whisperx"
```

WhisperKit can be configured with:

```bash
export SHADOW_COACH_WHISPERKIT_COMMAND="/path/to/whisperkit-cli"
```

## Optional Azure Configuration

Copy `config/provider-config.example.json` to:

```text
~/Library/Application Support/ShadowCoach/provider-config.json
```

Fill in only your own credentials. Never place the configured file in the repository or a shared bundle.

## Troubleshooting

Run:

```bash
./scripts/doctor.sh
```

The command reports required failures separately from optional capabilities. The app remains usable when optional tools are unavailable.
