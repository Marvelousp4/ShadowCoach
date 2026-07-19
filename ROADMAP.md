# Roadmap

The roadmap is ordered by user value and contributor leverage, not by novelty.

## Public Preview

- Signed and notarized macOS DMG with a tested first-run experience.
- Product screenshots and a short Import -> Repeat -> Diagnose demo.
- Dependency preflight inside the app, with one-click setup guidance.
- Redacted diagnostic export for useful bug reports.
- Subtitle segmentation regression fixtures for known difficult talks.

## Contributor-Friendly Core

- Extract persistent models and schema migrations from `ShadowCoachApp.swift`.
- Extract subtitle parsing and sentence segmentation with fixture tests.
- Extract transcript word diff and scoring rules with unit tests.
- Define provider protocols for transcription, pronunciation, translation, and coaching.
- Document `.shadowcoachbundle` as a versioned portable format.

## Cross-Device Practice

- Export/import only changed folders without requiring a server.
- Preserve favorites, completion, recordings, and cached results in the bundle schema.
- Add conflict-safe local merge rules.
- Evaluate optional iCloud Drive folder sync after the offline format is stable.

## Later, Not Required for Launch

- Limited web demo of the practice flow.
- App Store distribution.
- Additional languages and pronunciation providers.
- Optional community practice-pack index containing only licensed content.
