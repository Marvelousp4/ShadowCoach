# Privacy

Shadow Coach is local-first. Your library, imported media, recordings, history, and cached analysis are stored under `~/Library/Application Support/ShadowCoach/` on macOS or the app container on iPhone.

Data leaves the device only when you deliberately enable a remote provider:

- Azure Speech receives audio and reference text for pronunciation assessment.
- Azure Translator receives selected text for translation.
- Gemini receives the evidence included in the coaching prompt.
- Codex CLI behavior follows the user's local Codex configuration and account.
- URL import contacts the source website through yt-dlp or normal HTTP requests.

Before sharing logs or filing an issue, remove names, sentence content, file paths, URLs, transcripts, API keys, and recording identifiers that you do not want public.

Deleting the application does not necessarily delete its Application Support data. Users can remove that folder separately after exporting anything they want to keep.
