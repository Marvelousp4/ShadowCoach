# Dependency Distribution

The public repository should contain source code, small original assets, configuration examples, tests, and build scripts. It should not contain downloaded media, user data, credentials, large model weights, or arbitrary third-party binaries.

## Distribution Tiers

### 1. Built-in core

These features must work immediately after installing the signed app:

- Library browsing and persistence
- Apple TTS
- Reference playback for imported bundles
- Recording and playback
- Practice history and cached-result display
- Text and subtitle file import that does not require media conversion

### 2. Small external command-line tools

Use capability detection and guided installation for:

- `ffmpeg`
- `yt-dlp`

For developers, Homebrew is the simplest supported path. For normal users, a future in-app setup assistant may download verified release artifacts after their licenses and redistribution requirements are reviewed. Store downloaded tools under Application Support, verify a pinned SHA-256 checksum, and show their versions in diagnostics.

### 3. Models and heavyweight analysis runtimes

Do not commit Whisper model weights or a Python environment to Git. They are large, change independently, and may have separate model licenses.

- Prefer a native Swift/Apple Silicon transcription package for the default local path.
- Download the selected model on first use with size, license, and storage information visible before download.
- Keep WhisperX as an advanced developer/research option until its Python, PyTorch, alignment models, and platform packaging are reliable.
- Keep Parselmouth optional initially; longer term, move the small set of required acoustic features to a native Swift/Accelerate implementation or ship a separately audited helper.

### 4. Remote and user-owned providers

Azure, Gemini, and Codex CLI remain optional. The app must clearly show which provider will receive data before analysis. A missing provider must never break local practice.

## Linking Rules

- Use Swift Package Manager only for compatible source packages.
- A GitHub repository URL does not install a command-line program by itself.
- Git submodules are appropriate for source maintained as part of the build, not model weights or user-facing runtime installation.
- GitHub Releases can host versioned helper archives, but the app must download a pinned version, verify its checksum, and comply with the helper's license.
- Git LFS is not the default model delivery mechanism; it makes clones slower and does not solve runtime updates or license consent.

## Recommended Public Preview

For `v0.1`:

1. Ship one signed and notarized app containing the dependency-free core.
2. Detect `ffmpeg`, `yt-dlp`, WhisperX, and Parselmouth with `scripts/doctor.sh` and in-app preflight.
3. Document Homebrew/Python setup for advanced local analysis.
4. Keep Azure and Gemini opt-in.
5. Add native on-demand transcription in a later release to make local analysis truly one-click.

## Reproducible developer setup

The repository now includes:

```text
Brewfile                         ffmpeg, yt-dlp, Python 3.11
requirements/local-analysis.txt pinned WhisperX and Parselmouth versions
config/tool-manifest.json        machine-readable capability ownership
scripts/install-local-tools.sh   media and analysis installer
scripts/doctor.sh                runtime verification
```

Install only what you need:

```bash
./scripts/install-local-tools.sh --media
./scripts/install-local-tools.sh --analysis
./scripts/install-local-tools.sh --all
```

The analysis environment is installed outside the repository at `~/.local/share/shadowcoach-whisperx-venv` by default, which is also the path the app discovers automatically.
