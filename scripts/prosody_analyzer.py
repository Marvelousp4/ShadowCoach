#!/usr/bin/env python3
import argparse
import json
import math
import os
import subprocess
import tempfile

import parselmouth


def run_ffmpeg(input_path, output_path, start=None, end=None):
    command = ["ffmpeg", "-y"]
    if start is not None:
        command += ["-ss", str(max(0.0, start))]
    command += ["-i", input_path]
    if start is not None and end is not None and end > start:
        command += ["-t", str(end - start)]
    command += ["-ac", "1", "-ar", "16000", output_path]
    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


def quantile(values, q):
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(round((len(ordered) - 1) * q))))
    return ordered[index]


def downsample(points, limit=90):
    if len(points) <= limit:
        return points
    step = len(points) / limit
    sampled = []
    for i in range(limit):
        sampled.append(points[int(i * step)])
    return sampled


def contiguous_windows(points, threshold):
    windows = []
    start = None
    last_t = None
    for point in points:
        active = point["value"] >= threshold
        if active and start is None:
            start = point["time"]
        if not active and start is not None and last_t is not None:
            if last_t - start >= 0.08:
                windows.append({"start": start, "end": last_t})
            start = None
        last_t = point["time"]
    if start is not None and last_t is not None and last_t - start >= 0.08:
        windows.append({"start": start, "end": last_t})
    return windows[:8]


def analyze_one(path, word_count=0, start=None, end=None):
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "audio.wav")
        run_ffmpeg(path, wav, start, end)
        sound = parselmouth.Sound(wav)
        duration = float(sound.duration)
        pitch = sound.to_pitch(time_step=0.02, pitch_floor=75, pitch_ceiling=500)
        intensity = sound.to_intensity(time_step=0.02)

        pitch_points = []
        for i in range(1, pitch.get_number_of_frames() + 1):
            t = pitch.get_time_from_frame_number(i)
            value = pitch.get_value_in_frame(i)
            if value and math.isfinite(value):
                pitch_points.append({"time": round(float(t), 3), "value": round(float(value), 2)})

        intensity_points = []
        for i in range(1, intensity.get_number_of_frames() + 1):
            t = intensity.get_time_from_frame_number(i)
            value = intensity.get_value(t)
            if value and math.isfinite(value):
                intensity_points.append({"time": round(float(t), 3), "value": round(float(value), 2)})

        intensity_values = [p["value"] for p in intensity_points]
        pitch_values = [p["value"] for p in pitch_points]
        silence_threshold = max(35.0, quantile(intensity_values, 0.20))
        emphasis_threshold = quantile(intensity_values, 0.82)

        pauses = contiguous_windows(
            [{"time": p["time"], "value": -p["value"]} for p in intensity_points],
            -silence_threshold,
        )
        pauses = [w for w in pauses if w["end"] - w["start"] >= 0.18]
        emphasis_windows = contiguous_windows(intensity_points, emphasis_threshold)

        return {
            "duration": round(duration, 3),
            "speakingRateWpm": round((word_count / duration) * 60.0, 1) if word_count and duration > 0 else 0,
            "pauseCount": len(pauses),
            "pauseDuration": round(sum(w["end"] - w["start"] for w in pauses), 3),
            "meanPitch": round(sum(pitch_values) / len(pitch_values), 2) if pitch_values else 0,
            "meanIntensity": round(sum(intensity_values) / len(intensity_values), 2) if intensity_values else 0,
            "pitchCurve": downsample(pitch_points),
            "intensityCurve": downsample(intensity_points),
            "emphasisWindows": emphasis_windows,
        }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--user-audio", required=True)
    parser.add_argument("--reference-audio")
    parser.add_argument("--reference-start", type=float)
    parser.add_argument("--reference-end", type=float)
    parser.add_argument("--user-word-count", type=int, default=0)
    parser.add_argument("--target-word-count", type=int, default=0)
    args = parser.parse_args()

    result = {
        "user": analyze_one(args.user_audio, word_count=args.user_word_count),
        "reference": None,
    }
    if args.reference_audio:
        result["reference"] = analyze_one(
            args.reference_audio,
            word_count=args.target_word_count,
            start=args.reference_start,
            end=args.reference_end,
        )
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
