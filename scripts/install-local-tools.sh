#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${SHADOW_COACH_ANALYSIS_HOME:-$HOME/.local/share/shadowcoach-whisperx-venv}"
install_media=false
install_analysis=false

usage() {
  cat <<'USAGE'
Usage: ./scripts/install-local-tools.sh [--media] [--analysis] [--all]

  --media     Install ffmpeg and yt-dlp with Homebrew.
  --analysis  Create the local WhisperX/Parselmouth Python environment.
  --all       Install both groups.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --media) install_media=true ;;
    --analysis) install_analysis=true ;;
    --all) install_media=true; install_analysis=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$install_media" == false && "$install_analysis" == false ]]; then
  usage
  exit 2
fi

if [[ "$install_media" == true ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo 'Homebrew is required for --media: https://brew.sh' >&2
    exit 1
  fi
  brew bundle --file "$ROOT_DIR/Brewfile"
fi

if [[ "$install_analysis" == true ]]; then
  python="${SHADOW_COACH_BOOTSTRAP_PYTHON:-}"
  if [[ -z "$python" ]] && command -v brew >/dev/null 2>&1; then
    brew_python="$(brew --prefix python@3.11 2>/dev/null)/bin/python3.11"
    if [[ ! -x "$brew_python" ]]; then
      echo 'Installing the supported Python 3.11 runtime with Homebrew...'
      brew install python@3.11
      brew_python="$(brew --prefix python@3.11)/bin/python3.11"
    fi
    if [[ -x "$brew_python" ]]; then
      python="$brew_python"
    fi
  fi
  if [[ -z "$python" ]] && command -v python3.11 >/dev/null 2>&1; then
    python="$(command -v python3.11)"
  fi
  if [[ -z "$python" ]] && command -v python3 >/dev/null 2>&1; then
    python="$(command -v python3)"
  fi
  if [[ -z "$python" ]]; then
    echo 'Python 3.11 is required. Install it with: brew install python@3.11' >&2
    exit 1
  fi

  if ! "$python" -c 'import sys; raise SystemExit(0 if (3, 10) <= sys.version_info[:2] < (3, 14) else 1)'; then
    echo "WhisperX requires Python 3.10–3.13, but $python is $("$python" --version 2>&1)." >&2
    echo 'Install Python 3.11 with Homebrew or set SHADOW_COACH_BOOTSTRAP_PYTHON.' >&2
    exit 1
  fi

  "$python" -m venv --clear "$VENV_DIR"
  "$VENV_DIR/bin/python" -m pip install --upgrade pip
  "$VENV_DIR/bin/python" -m pip install -r "$ROOT_DIR/requirements/local-analysis.txt"
fi

echo
echo 'Installed capabilities:'
"$ROOT_DIR/scripts/doctor.sh"
