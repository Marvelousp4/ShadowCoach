#!/usr/bin/env python3
"""Fast transcript-only path for short Shadow Coach recordings."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from faster_whisper import WhisperModel


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--model", default="small")
    parser.add_argument("--hotwords", default="")
    args = parser.parse_args()

    model = WhisperModel(args.model, device="cpu", compute_type="int8")
    segment_stream, _ = model.transcribe(
        args.audio,
        language="en",
        beam_size=1,
        best_of=1,
        temperature=0.0,
        condition_on_previous_text=False,
        word_timestamps=False,
        vad_filter=False,
        hotwords=args.hotwords or None,
    )
    segments = [
        {
            "text": segment.text.strip(),
            "start": segment.start,
            "end": segment.end,
        }
        for segment in segment_stream
        if segment.text.strip()
    ]
    payload = {
        "transcript": " ".join(segment["text"] for segment in segments).strip(),
        "segments": segments,
    }
    Path(args.output).write_text(
        json.dumps(payload, ensure_ascii=False),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
