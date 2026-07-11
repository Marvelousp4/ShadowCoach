#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/shadowcoach-clean-room.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

mkdir -p "$SANDBOX/home"
git clone --quiet --no-local "$ROOT_DIR" "$SANDBOX/ShadowCoach"
cd "$SANDBOX/ShadowCoach"

for forbidden in provider-config.json ShadowCoachMobileDocuments; do
  if find . -name "$forbidden" -print -quit | grep -q .; then
    echo "Clean-room clone contains forbidden runtime data: $forbidden" >&2
    exit 1
  fi
done

if find . -type f \( -name '*.m4a' -o -name '*.mp4' -o -name '*.shadowcoachbundle' \) -print -quit | grep -q .; then
  echo 'Clean-room clone contains user media or an exported bundle.' >&2
  exit 1
fi

clean_env=(
  env -i
  "HOME=$SANDBOX/home"
  "CFFIXED_USER_HOME=$SANDBOX/home"
  USER=shadowcoach-test
  LOGNAME=shadowcoach-test
  PATH=/usr/bin:/bin:/usr/sbin:/sbin
  "TMPDIR=${TMPDIR:-/tmp}"
)

"${clean_env[@]}" ./scripts/bootstrap.sh
"${clean_env[@]}" swift test
"${clean_env[@]}" swift build -c release

echo 'Clean-room core build passed.'
