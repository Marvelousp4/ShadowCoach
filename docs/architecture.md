# Architecture

## Product Boundaries

The macOS app owns importing, library management, local analysis orchestration, and bundle export. The iPhone companion owns portable practice, recording, local progress, imported analysis display, and optional Azure assessment. A `.shadowcoachbundle` is currently the offline transfer boundary.

## Analysis Responsibilities

```text
User recording
  -> WhisperX: what the user actually said and word timestamps
  -> Azure (optional): similarity to reference, word/phoneme evidence
  -> Praat/Parselmouth: duration, pauses, pitch, intensity
  -> deterministic rules: learning issue candidates
  -> Codex or Gemini (optional): explain evidence in plain language
  -> local cache: persist results by recording and provider
```

The LLM explains evidence; it must not invent the pronunciation score.

## Current Source Layout

The macOS prototype currently lives in `Sources/ShadowCoach/main.swift`. This preserves a working product but creates a contribution bottleneck. Refactoring should be incremental and behavior-preserving.

Target modules:

```text
App/              app lifecycle and commands
Models/           Codable domain models and migrations
Persistence/      library, practice history, cache, Keychain
Audio/            playback, recording, clipping, TTS
Import/           text, subtitle, media, and URL pipelines
Analysis/         transcript, word diff, prosody, Azure, rules
Providers/        Codex, Gemini, translator adapters
Views/            Library, Practice, Feedback, Settings
```

## Contribution Rules

- Keep runtime data outside the repository.
- Version persistent schemas and migrate old data.
- Treat external tools as optional capabilities.
- Cache deterministic and paid analysis results separately.
- Keep Azure as the reference-aligned scoring source and WhisperX as the free transcript source.
- Add fixtures for every subtitle segmentation regression.
