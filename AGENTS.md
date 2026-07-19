# Shadow Coach Contribution Rules

## Delivery Workflow

- After each completed user-requested code change, run the relevant tests and build checks, then commit and push the verified change to GitHub unless the user explicitly requests local-only work.
- Small, self-contained fixes may be pushed to the current branch. Larger or riskier features should use a `codex/` branch and be pushed as a reviewable pull request.
- Keep commits focused and describe the user-visible behavior in the commit message.
- Never commit or push API keys, provider credentials, personal recordings, imported media, runtime libraries, caches, or other private user data.
- Keep generated application bundles and release media out of normal source commits; publish distributable binaries through GitHub Releases when requested.
