#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

"$ROOT_DIR/scripts/doctor.sh"

if command -v brew >/dev/null 2>&1; then
  missing=()
  command -v ffmpeg >/dev/null 2>&1 || missing+=(ffmpeg)
  command -v yt-dlp >/dev/null 2>&1 || missing+=(yt-dlp)
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo
    printf 'Recommended optional tools are missing: %s\n' "${missing[*]}"
    printf 'Install them with: brew install %s\n' "${missing[*]}"
  fi
fi

echo
echo 'Resolving and building the Swift package...'
swift package resolve
swift build
echo
echo 'Ready. Run: swift run ShadowCoach'
echo 'Optional full local stack: ./scripts/install-local-tools.sh --all'
