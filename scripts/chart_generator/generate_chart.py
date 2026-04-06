#!/usr/bin/env python3
"""
音乐乐谱生成脚本 v2
使用 librosa 分析音频，生成下落式音游的乐谱 JSON
根据音乐能量动态调整难度，支持主动生成 hold 和 slide
"""

import argparse
import json
import random
import sys
from pathlib import Path

# Magic number constants
MIN_BEAT_INTERVAL_MS = 150  # 最小节拍间隔（ms），低于此认为是快速段
MAX_HOLD_DURATION_MS = 1500  # 最大 hold 时长
SLIDE_PROBABILITY = 0.25  # 滑动音符概率
HOLD_PROBABILITY = 0.35  # Hold 音符概率（提高）
RANDOM_COLUMN_PROBABILITY = 0.7  # 随机 column 的概率
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


def detect_beats_with_energy(audio_path, bpm):
    """检测节拍时间点（ms）和能量（基于 RMS 音量）"""
    y, sr = librosa.load(audio_path)

    # 使用 RMS 音量作为能量指标
    rms = librosa.feature.rms(y=y)[0]

    # 获取 beats
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    beats = librosa.beat.beat_track(
        onset_envelope=onset_env,
        sr=sr,
        bpm=bpm,
        tightness=100,
    )[1]

    beat_times = librosa.frames_to_time(beats, sr=sr)

    # 计算每个 beat 对应的帧
    beat_frames = librosa.time_to_frames(beat_times, sr=sr)

    # 获取每个 beat 的 RMS 能量
    energies = []
    for frame in beat_frames:
        if frame < len(rms):
            energies.append(float(rms[frame]))
        else:
            energies.append(0.0)

    return [int(t * 1000) for t in beat_times], energies


def generate_notes(beat_times, energies, bpm, column_count=3):
    """根据节拍生成音符，根据能量动态调整"""
    notes = []
    beat_interval_ms = 60000 / bpm

    # 计算能量统计（librosa 的 onset_strength 是相对值，需要归一化）
    if energies and max(energies) > 0:
        avg_energy = sum(energies) / len(energies)
        max_energy = max(energies)
        high_energy_threshold = avg_energy + (max_energy - avg_energy) * 0.6
    else:
        avg_energy = 0.5
        high_energy_threshold = 0.65

    for i, (beat_time, energy) in enumerate(zip(beat_times, energies)):
        if i < 2:
            continue

        # 随机决定 column（增加趣味性）
        if random.random() < RANDOM_COLUMN_PROBABILITY:
            column = random.randint(0, column_count - 1)
        else:
            column = i % column_count

        # 检测是否是快速段（节拍间隔小）
        is_fast = False
        if i > 0:
            interval = beat_time - beat_times[i - 1]
            is_fast = interval < MIN_BEAT_INTERVAL_MS

        # 高能量段：更大概率生成特殊音符
        is_high_energy = energy > high_energy_threshold if max(energies) > 0 else False

        # 额外随机判断（增加多样性）
        use_hold = random.random() < 0.12  # 12% 基础 hold 概率

        # Slide 音符：高能量段或随机概率
        if (is_high_energy or random.random() < SLIDE_PROBABILITY * 0.3) and not is_fast:
            directions = ["up", "down", "left", "right"]
            notes.append({
                "time": beat_time,
                "column": column,
                "type": "slide",
                "direction": random.choice(directions),
            })
            continue

        # Hold 音符：高能量段或随机概率，hold 时长根据能量和节拍间隔计算
        if use_hold or (is_high_energy and random.random() < HOLD_PROBABILITY):
            # 根据能量决定 hold 时长（高能量 = 长 hold）
            energy_factor = min(energy / max(high_energy_threshold, 0.01), 2.0)
            hold_duration = int(min(MAX_HOLD_DURATION_MS, beat_interval_ms * energy_factor * random.uniform(0.8, 1.5)))
            notes.append({
                "time": beat_time,
                "column": column,
                "type": "hold",
                "holdDuration": hold_duration,
            })
            continue

        # 快速段：生成短 tap 或 double tap（两列同时）
        if is_fast and i > 0:
            interval = beat_times[i] - beat_times[i - 1]
            if interval < 120 and random.random() < 0.3:
                # Double tap：同一列紧接一个 tap
                notes.append({
                    "time": beat_time,
                    "column": column,
                    "type": "tap",
                })
                if random.random() < 0.5:
                    # 额外在相邻列加一个 tap
                    next_col = (column + 1) % column_count
                    notes.append({
                        "time": beat_time + int(interval * 0.5),
                        "column": next_col,
                        "type": "tap",
                    })
                continue

        # 普通 tap
        notes.append({
            "time": beat_time,
            "column": column,
            "type": "tap",
        })

    # 添加一些主动设计的 hold 模式（连续 hold）
    notes = add_hold_patterns(notes, beat_times, column_count)

    # 按时间排序
    notes.sort(key=lambda x: x["time"])

    return notes


def add_hold_patterns(notes, beat_times, column_count):
    """添加有节奏感的 hold 模式"""
    if len(beat_times) < 8:
        return notes

    # 在歌曲中间段随机插入一些 hold 模式
    total_beats = len(beat_times)
    middle_start = total_beats // 4
    middle_end = total_beats * 3 // 4

    # 随机选择几个位置插入 hold 链
    num_patterns = random.randint(1, 3)
    for _ in range(num_patterns):
        start_idx = random.randint(middle_start, middle_end - 4)
        column = random.randint(0, column_count - 1)

        # 创建 2-4 个连续的 hold
        num_holds = random.randint(2, 4)
        for j in range(num_holds):
            if start_idx + j * 2 < len(beat_times):
                beat_time = beat_times[start_idx + j * 2]
                hold_duration = random.randint(400, 1000)

                # 检查该时间点是否已有音符
                existing = [n for n in notes if abs(n["time"] - beat_time) < 100]
                if not existing:
                    notes.append({
                        "time": beat_time,
                        "column": column,
                        "type": "hold",
                        "holdDuration": hold_duration,
                    })

    return notes


def generate_chart(audio_path, output_path, song_name=None, artist=None, intro=""):
    """生成完整乐谱"""
    print(f"Analyzing: {audio_path}")

    bpm = detect_bpm(audio_path)
    print(f"BPM detected: {bpm:.2f}")

    beat_times, energies = detect_beats_with_energy(audio_path, bpm)
    print(f"Beats detected: {len(beat_times)}")
    print(f"Average energy: {sum(energies)/len(energies):.3f}")

    notes = generate_notes(beat_times, energies, bpm)
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
    parser = argparse.ArgumentParser(description="生成音游乐谱 v2")
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
