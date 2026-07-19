# Third-Party Tools and Services

Shadow Coach can interoperate with the following independently distributed tools and services. They are not relicensed by this repository and are not bundled in source releases unless a release explicitly says otherwise.

| Component | Purpose | Distribution |
|---|---|---|
| [FFmpeg](https://ffmpeg.org/) | Media decoding and conversion | Installed separately |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | URL metadata, media, and subtitle retrieval | Installed separately |
| [WhisperX](https://github.com/m-bain/whisperX) | Local speech recognition and alignment | Installed separately |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Optional Apple-platform transcription fallback | Installed separately |
| [Praat/Parselmouth](https://github.com/YannickJadoul/Parselmouth) | Local acoustic and prosody measurements | Installed separately |
| [Codex CLI](https://github.com/openai/codex) | Optional local coaching provider | Installed separately |
| [FSRS-6 / py-fsrs](https://github.com/open-spaced-repetition/py-fsrs) | Local adaptive review scheduling | Reimplemented in Swift; MIT notice included |
| Azure AI Speech | Optional pronunciation assessment | Remote service |
| Azure Translator | Optional translation | Remote service |
| Gemini API | Optional coaching provider | Remote service |

Users and redistributors are responsible for complying with each component's license, model license, service terms, and local law. Do not redistribute downloaded media or subtitles without permission.

The py-fsrs MIT notice is included at [LICENSES/py-fsrs-MIT.txt](LICENSES/py-fsrs-MIT.txt).
