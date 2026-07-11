#!/usr/bin/env bash
set -uo pipefail

failures=0

check_required() {
  local label="$1"
  local command="$2"
  if command -v "$command" >/dev/null 2>&1; then
    printf 'OK       %-20s %s\n' "$label" "$(command -v "$command")"
  else
    printf 'MISSING  %-20s required\n' "$label"
    failures=$((failures + 1))
  fi
}

check_optional() {
  local label="$1"
  local command="$2"
  if command -v "$command" >/dev/null 2>&1; then
    printf 'OK       %-20s %s\n' "$label" "$(command -v "$command")"
  else
    printf 'OPTIONAL %-20s not installed\n' "$label"
  fi
}

echo 'Shadow Coach environment'
check_required 'Swift' swift
check_required 'codesign' codesign
check_optional 'FFmpeg' ffmpeg
check_optional 'yt-dlp' yt-dlp
check_optional 'Codex CLI' codex

whisperx="${SHADOW_COACH_WHISPERX_COMMAND:-$HOME/.local/share/shadowcoach-whisperx-venv/bin/whisperx}"
if [[ -x "$whisperx" ]] || command -v "$whisperx" >/dev/null 2>&1; then
  printf 'OK       %-20s %s\n' 'WhisperX' "$whisperx"
else
  printf 'OPTIONAL %-20s set SHADOW_COACH_WHISPERX_COMMAND\n' 'WhisperX'
fi

default_python="$HOME/.local/share/shadowcoach-whisperx-venv/bin/python"
if [[ ! -x "$default_python" ]]; then
  default_python="python3"
fi
python="${SHADOW_COACH_PYTHON:-$default_python}"
if "$python" -c 'import parselmouth' >/dev/null 2>&1; then
  printf 'OK       %-20s %s\n' 'Parselmouth' "$python"
else
  printf 'OPTIONAL %-20s install praat-parselmouth\n' 'Parselmouth'
fi

if [[ $failures -gt 0 ]]; then
  echo
  echo "Environment has $failures required problem(s)."
  exit 1
fi

echo
echo 'Required environment is ready. Optional rows enable advanced features.'
