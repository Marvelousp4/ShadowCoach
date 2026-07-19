# Contributing

Thank you for helping make deliberate English speaking practice more useful and understandable.

## Start Here

1. Fork and clone the repository.
2. Run `./scripts/bootstrap.sh`.
3. Run `swift test` before changing code.
4. Keep each pull request focused on one behavior.
5. Add or update tests for parsing, persistence, scoring, or import logic changes.

## Development Commands

```bash
swift run ShadowCoach
swift test
./scripts/build-app.sh
./scripts/doctor.sh
```

The iPhone project is opened with `open ios/ShadowCoachMobile.xcodeproj` and built in Xcode.

## Pull Requests

- Describe the user problem and the behavior after the change.
- Include screenshots or a short recording for visible UI changes.
- State which checks you ran.
- Preserve backward compatibility for `library.json`, `practice.json`, analysis caches, and `.shadowcoachbundle` unless the change includes a migration.
- Do not commit generated builds, media, transcripts, recordings, model weights, logs, or credentials.

## Code Style

- Follow existing SwiftUI patterns and Apple Human Interface Guidelines.
- Keep views focused and move reusable domain logic out of views.
- Prefer Codable models and structured parsers over string rewriting.
- Keep optional integrations behind clear capability checks and actionable errors.
- Add comments only when the reason is not obvious from the code.

## Reporting Bugs

Use the bug template. Include macOS/iOS version, app revision, exact steps, expected behavior, actual behavior, and the relevant redacted log excerpt. Replace private sentence text when it is not necessary to reproduce the issue.

## Good First Contributions

- Parser fixtures and regression tests.
- Accessibility labels and VoiceOver fixes.
- Documentation and setup diagnostics.
- Small extractions from `ShadowCoachApp.swift` that do not change behavior.
- Clearer actionable errors for missing optional tools.
