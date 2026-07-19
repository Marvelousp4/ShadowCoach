# Clean-Room Testing

`scripts/clean-room-smoke.sh` verifies the dependency-free contributor path from a fresh local clone and an isolated HOME:

```bash
./scripts/clean-room-smoke.sh
```

It confirms that:

- only committed files are available;
- personal media, provider config, recordings, and bundles are absent;
- optional tools may be missing without breaking the core build;
- `scripts/bootstrap.sh`, `swift test`, and the release build succeed.

The deeper manual release audit also installs local analysis into a temporary HOME, generates an original TTS fixture, runs WhisperX with `small`, checks word timestamps, and runs `prosody_analyzer.py`. This deeper test downloads approximately 1–2 GB and is intentionally not part of every CI run.

For runtime isolation testing, launch with a temporary `CFFIXED_USER_HOME`; do not point test runs at a real user's Application Support directory.
