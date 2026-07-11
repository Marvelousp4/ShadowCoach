# Setup

## Required

- macOS 13 or newer
- Xcode Command Line Tools: `xcode-select --install`

## Recommended Import Tools

```bash
brew install ffmpeg yt-dlp
```

## Optional Prosody Analysis

Use an isolated Python environment:

```bash
python3 -m venv ~/.local/share/shadowcoach-analysis-venv
~/.local/share/shadowcoach-analysis-venv/bin/pip install praat-parselmouth
export SHADOW_COACH_PYTHON="$HOME/.local/share/shadowcoach-analysis-venv/bin/python"
```

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
