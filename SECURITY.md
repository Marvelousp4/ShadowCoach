# Security Policy

## Reporting a Vulnerability

Do not open a public issue for credential exposure, unsafe file handling, or a privacy vulnerability. Contact the maintainer privately through the security contact configured on the GitHub repository.

Include affected version, reproduction steps, impact, and a minimal proof of concept. Do not include real API keys, private recordings, or copyrighted media.

## Credentials

- Shadow Coach never requires credentials to be committed to source control.
- Gemini credentials should be stored in Keychain through the app.
- Azure development configuration belongs in `~/Library/Application Support/ShadowCoach/provider-config.json` and is ignored by Git.
- Use `config/provider-config.example.json` only as a schema example.
- Rotate a credential immediately if it appears in a terminal transcript, screenshot, issue, commit, or chat.
