# Release Checklist

1. Rotate any credential that has appeared in a chat, log, screenshot, or test bundle.
2. Run `./scripts/doctor.sh`, `swift test`, and `swift build -c release`.
3. Confirm `git status --ignored` contains no personal media, recordings, bundles, provider config, or models in tracked files.
4. Update `CHANGELOG.md` and the app version.
5. Build with `SHADOW_COACH_SIGN_IDENTITY` set to a Developer ID Application identity.
6. Package with `SHADOW_COACH_NOTARY_PROFILE` configured.
7. Verify the DMG on a different Mac user account or clean machine.
8. Create a GitHub Release with the DMG, checksums, release notes, and known limitations.
9. Test the README download link and first-run workflow.
