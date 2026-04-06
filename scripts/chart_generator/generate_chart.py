#!/usr/bin/env python3
"""
音乐乐谱生成脚本
使用 librosa 分析音频，生成下落式音游的乐谱 JSON
"""

import argparse
import json
import random
import sys
from pathlib import Path

# Magic number constants
HOLD_THRESHOLD_MULTIPLIER = 1.5
MAX_HOLD_DURATION_MS = 1500
SLIDE_PROBABILITY = 0.1
SLIDE_CHECK_INTERVAL = 4
DEFAULT_DURATION = 180
DEFAULT_DIFFICULTY = 3
DEFAULT_DROP_DURATION = 2500

try:
    import librosa
    import numpy as np
except ImportError:
    print("Error: librosa not installed. Run: pip install -r requirements.txt")
    sys.exit(1)


def detect_bpm(audio_path):
    """检测音频BPM"""
    y, sr = librosa.load(audio_path)
    tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
    return float(tempo)


def detect_beats(audio_path, bpm):
    """检测节拍时间点（ms）"""
    y, sr = librosa.load(audio_path)

    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    beats = librosa.beat.beat_track(
        onset_envelope=onset_env,
        sr=sr,
        bpm=bpm,
        tightness=100,
    )[1]

    beat_times = librosa.frames_to_time(beats, sr=sr)
    return [int(t * 1000) for t in beat_times]


def generate_notes(beat_times, bpm, column_count=3):
    """根据节拍生成音符"""
    notes = []
    beat_interval_ms = 60000 / bpm
    hold_threshold = beat_interval_ms * HOLD_THRESHOLD_MULTIPLIER

    for i, beat_time in enumerate(beat_times):
        if i < 2:
            continue

        column = i % column_count

        if i > 0:
            prev_beat = beat_times[i - 1]
            interval = beat_time - prev_beat

            if interval > hold_threshold:
                hold_duration = min(int(interval), MAX_HOLD_DURATION_MS)
                notes.append({
                    "time": beat_time,
                    "column": column,
                    "type": "hold",
                    "holdDuration": hold_duration,
                })
                continue

        if i % SLIDE_CHECK_INTERVAL == 0 and i > 0:
            if random.random() < SLIDE_PROBABILITY:
                directions = ["up", "down", "left", "right"]
                notes.append({
                    "time": beat_time,
                    "column": column,
                    "type": "slide",
                    "direction": directions[random.randint(0, 3)],
                })
                continue

        notes.append({
            "time": beat_time,
            "column": column,
            "type": "tap",
        })

    return notes


def generate_chart(audio_path, output_path, song_name=None, artist=None, intro=""):
    """生成完整乐谱"""
    print(f"Analyzing: {audio_path}")

    bpm = detect_bpm(audio_path)
    print(f"BPM detected: {bpm}")

    beat_times = detect_beats(audio_path, bpm)
    print(f"Beats detected: {len(beat_times)}")

    notes = generate_notes(beat_times, bpm)
    print(f"Notes generated: {len(notes)}")

    chart = {
        "id": Path(audio_path).stem,
        "name": song_name or Path(audio_path).stem,
        "artist": artist or "Unknown",
        "intro": intro,
        "audioPath": f"assets/audio/{Path(audio_path).name}",
        "coverPath": f"assets/covers/{Path(audio_path).stem}.png",
        "bpm": int(bpm),
        "duration": DEFAULT_DURATION,
        "difficulty": DEFAULT_DIFFICULTY,
        "dropDuration": DEFAULT_DROP_DURATION,
        "notes": notes,
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(chart, f, indent=2, ensure_ascii=False)

    print(f"Chart saved to: {output_path}")

    tap_count = sum(1 for n in notes if n["type"] == "tap")
    hold_count = sum(1 for n in notes if n["type"] == "hold")
    slide_count = sum(1 for n in notes if n["type"] == "slide")
    print(f"  Tap: {tap_count}, Hold: {hold_count}, Slide: {slide_count}")


def main():
    parser = argparse.ArgumentParser(description="生成音游乐谱")
    parser.add_argument("audio", help="音频文件路径 (m4a, mp3, wav)")
    parser.add_argument("-o", "--output", help="输出JSON路径")
    parser.add_argument("--name", help="歌曲名称")
    parser.add_argument("--artist", help="艺术家名称")
    parser.add_argument("--intro", default="", help="简介")

    args = parser.parse_args()

    audio_path = Path(args.audio)
    if not audio_path.exists():
        print(f"Error: File not found: {audio_path}")
        sys.exit(1)

    output_path = args.output or f"assets/charts/{audio_path.stem}.json"

    generate_chart(
        str(audio_path),
        output_path,
        song_name=args.name,
        artist=args.artist,
        intro=args.intro,
    )


if __name__ == "__main__":
    main()
