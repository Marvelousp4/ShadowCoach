#!/usr/bin/env bash
set -uo pipefail

failures=0

echo 'Shadow Coach release environment'

if security find-identity -v -p codesigning | grep -q 'Developer ID Application:'; then
  security find-identity -v -p codesigning | grep 'Developer ID Application:'
else
  echo 'MISSING  Developer ID Application certificate'
  failures=$((failures + 1))
fi

if [[ -n "${SHADOW_COACH_SIGN_IDENTITY:-}" ]]; then
  echo "OK       SHADOW_COACH_SIGN_IDENTITY is set"
else
  echo 'MISSING  SHADOW_COACH_SIGN_IDENTITY'
  failures=$((failures + 1))
fi

if [[ -n "${SHADOW_COACH_NOTARY_PROFILE:-}" ]]; then
  echo "OK       SHADOW_COACH_NOTARY_PROFILE is set"
else
  echo 'MISSING  SHADOW_COACH_NOTARY_PROFILE'
  failures=$((failures + 1))
fi

if [[ $failures -gt 0 ]]; then
  echo
  echo "Release setup has $failures blocking problem(s)."
  echo 'See docs/signing-and-notarization.md.'
  exit 1
fi

echo
echo 'Release signing configuration is ready.'
