#!/usr/bin/env python3
"""
音乐乐谱生成脚本 v3
使用 librosa 分析音频，生成下落式音游的乐谱 JSON
根据音乐能量动态调整难度，支持主动生成 hold 和 slide

碰撞规则（统一模型）：
  - 每个音符占用列的时间窗口 [event.time, event.time + duration + MISS_WINDOW_MS]
  - 同列下一个音符的 event.time 必须 > 上一音符的 end
"""

import argparse
import json
import random
import sys
from pathlib import Path

# Magic number constants
MIN_BEAT_INTERVAL_MS = 150  # 最小节拍间隔（ms），低于此认为是快速段
MAX_HOLD_DURATION_MS = 1500  # 最大 hold 时长
MIN_HOLD_DURATION_MS = 300  # 最小 hold 时长（确保 hold 有意义）
SLIDE_PROBABILITY = 0.40  # Slide 音符基础概率（目标 30%）
HOLD_PROBABILITY = 0.20  # Hold 音符基础概率（目标 15%）
DOUBLE_TAP_PROBABILITY = 0.80  # 双击概率（提高难度）
RANDOM_COLUMN_PROBABILITY = 0.5  # 随机 column 的概率
DEFAULT_DURATION = 180
DEFAULT_DIFFICULTY = 3
DEFAULT_DROP_DURATION = 2500
# 判定窗口（与游戏代码保持一致）
MISS_WINDOW_MS = 200
# 下落时间比例（与游戏代码保持一致）


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

    rms = librosa.feature.rms(y=y)[0]

    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    beats = librosa.beat.beat_track(
        onset_envelope=onset_env,
        sr=sr,
        bpm=bpm,
        tightness=100,
    )[1]

    beat_times = librosa.frames_to_time(beats, sr=sr)
    beat_frames = librosa.time_to_frames(beat_times, sr=sr)

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

    # 能量统计
    if energies and max(energies) > 0:
        avg_energy = sum(energies) / len(energies)
        max_energy = max(energies)
        high_energy_threshold = avg_energy + (max_energy - avg_energy) * 0.5
        low_energy_threshold = avg_energy * 0.4
    else:
        avg_energy = 0.5
        max_energy = 1.0
        high_energy_threshold = 0.65
        low_energy_threshold = 0.2

    # 每列的占用结束时间
    occupation_end = [0] * column_count

    def can_place(col, time, duration=0):
        """检查是否能放置（统一碰撞模型：event.time > 上一音符 end）"""
        return time > occupation_end[col]

    def place(col, time, ntype, duration=0, direction=None):
        """放置音符并更新占用"""
        end = time + duration + MISS_WINDOW_MS
        note = {"time": time, "column": col, "type": ntype}
        if duration > 0:
            note["holdDuration"] = duration
        if direction:
            note["direction"] = direction
        notes.append(note)
        if end > occupation_end[col]:
            occupation_end[col] = end
        return True

    def try_place_any_column(time, ntype, duration=0, direction=None):
        """尝试所有列，找到第一个可用的"""
        cols = list(range(column_count))
        random.shuffle(cols)
        for col in cols:
            if can_place(col, time, duration):
                place(col, time, ntype, duration, direction)
                return True
        return False

    def try_place_at_columns(cols, time, ntype, duration=0, direction=None):
        """尝试指定的列"""
        for col in cols:
            if can_place(col, time, duration):
                place(col, time, ntype, duration, direction)
                return True
        return False

    for i, (beat_time, energy) in enumerate(zip(beat_times, energies)):
        if i < 2:
            continue

        interval = beat_times[i] - beat_times[i - 1] if i > 0 else 9999
        is_fast = interval < MIN_BEAT_INTERVAL_MS
        is_high = energy > high_energy_threshold if max(energies) > 0 else False
        is_low = energy < low_energy_threshold

        # 根据列索引决定基础列
        base_col = i % column_count

        # ========== 快速段处理 ==========
        if is_fast and i > 0:
            short_interval = interval < 120

            if short_interval:
                # 短间隔：双击或三击
                if random.random() < DOUBLE_TAP_PROBABILITY:
                    # 双击：当前列 + 相邻列
                    placed = try_place_at_columns([base_col], beat_time, "tap")
                    next_col = (base_col + 1) % column_count
                    try_place_at_columns([next_col], beat_time + int(interval * 0.5), "tap")
                else:
                    # 单击
                    try_place_any_column(beat_time, "tap")
            else:
                # 中等间隔：单击
                try_place_any_column(beat_time, "tap")
            continue

        # ========== 正常段落处理 ==========
        # 目标分布：tap 55%，slide 30%，hold 15%

        roll = random.random()
        placed = False

        # 1. Slide（30%）
        if roll < 0.30:
            directions = ["up", "down", "left", "right"]
            if try_place_any_column(beat_time, "slide", direction=random.choice(directions)):
                placed = True

        # 2. Hold（15%）
        if not placed and roll < 0.45:
            # 能量驱动的 hold 时长：低能量 → 长 hold，高能量 → 短 hold
            energy_range = high_energy_threshold - low_energy_threshold
            if energy_range > 0:
                energy_ratio = (energy - low_energy_threshold) / energy_range
            else:
                energy_ratio = 0.5
            energy_ratio = max(0.0, min(1.0, energy_ratio))
            # 低能量(0.0) → 4x beats, 高能量(1.0) → 1x beats
            beat_mult = 1.0 + 3.0 * (1.0 - energy_ratio)
            hold_duration = int(beat_interval_ms * beat_mult)
            hold_duration = max(MIN_HOLD_DURATION_MS, min(MAX_HOLD_DURATION_MS, hold_duration))
            if try_place_any_column(beat_time, "hold", duration=hold_duration):
                placed = True

        # 3. Tap（55%）：上述都失败则放 tap
        if not placed:
            if not try_place_any_column(beat_time, "tap"):
                if i + 1 < len(beat_times):
                    next_time = beat_times[i + 1]
                    if next_time - beat_time < 300:
                        try_place_any_column(next_time, "tap")

    # 按时间排序
    notes.sort(key=lambda x: x["time"])
    return notes


def add_hold_patterns(notes, beat_times, column_count):
    """添加连续 hold 模式（带碰撞检测）"""
    if len(beat_times) < 8:
        return notes

    beat_interval_ms = 60000 / (random.uniform(60, 120))  # 随机 BPM 估算

    # 构建每列的占用结束时间（从已放置的音符，逐步更新）
    occupation_end = {}

    def can_place_hold(col, time, duration):
        # 只需检查 event_time > 上一音符的 end_time
        return time > occupation_end.get(col, 0)

    def place_hold(col, time, duration):
        end_time = time + duration + MISS_WINDOW_MS
        notes.append({
            "time": time,
            "column": col,
            "type": "hold",
            "holdDuration": duration,
        })
        if end_time > occupation_end.get(col, 0):
            occupation_end[col] = end_time

    total_beats = len(beat_times)
    middle_start = total_beats // 4
    middle_end = total_beats * 3 // 4

    # 插入 2-4 个 hold 链
    num_patterns = random.randint(2, 4)
    for _ in range(num_patterns):
        start_idx = random.randint(middle_start, max(middle_start, middle_end - 6))
        column = random.randint(0, column_count - 1)
        num_holds = random.randint(3, 5)

        for j in range(num_holds):
            idx = start_idx + j * 2
            if idx >= len(beat_times):
                break
            beat_time = beat_times[idx]
            # 每个 hold 至少 2 个 beat 的长度
            hold_duration = random.randint(
                max(MIN_HOLD_DURATION_MS, int(beat_interval_ms * 2)),
                min(MAX_HOLD_DURATION_MS, int(beat_interval_ms * 3.5))
            )
            # 检查 100ms 范围内没有其他音符
            existing = [n for n in notes if abs(n["time"] - beat_time) < 100]
            if not existing and can_place_hold(column, beat_time, hold_duration):
                place_hold(column, beat_time, hold_duration)

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


def rebuild_chart(input_path, output_path=None):
    """从现有乐谱重构，应用新的生成逻辑：
    1. 扩展 hold 时长
    2. 尝试在空隙处插入更多 tap/slide
    3. 确保无碰撞
    """
    with open(input_path, 'r', encoding='utf-8') as f:
        chart = json.load(f)

    drop_duration = chart.get("dropDuration", DEFAULT_DROP_DURATION)
    existing_notes = sorted(chart.get("notes", []), key=lambda x: x["time"])
    column_count = 3

    # occupation_end 按时间顺序逐步构建
    occupation_end = {}

    def can_place(col, time, duration=0):
        # collision window = [event_time, event_time + duration + MISS_WINDOW_MS]
        # 新音符的 event_time 必须 > 上一音符的 end_time（> 不是 >=，确保不重叠）
        return time > occupation_end.get(col, 0)

    def place(col, time, ntype, duration=0, direction=None):
        end_time = time + duration + MISS_WINDOW_MS
        note = {"time": time, "column": col, "type": ntype}
        if duration > 0:
            note["holdDuration"] = duration
        if direction:
            note["direction"] = direction
        if end_time > occupation_end.get(col, 0):
            occupation_end[col] = end_time
        return note

    kept_notes = []

    # 1. 先放置所有现有音符，尝试扩展 hold 时长
    for n in existing_notes:
        col = n["column"]
        time = n["time"]
        ntype = n["type"]
        duration = n.get("holdDuration", 0)
        direction = n.get("direction")

        if ntype == "hold":
            # 尝试扩展 hold 时长
            max_extend = int(DEFAULT_DROP_DURATION * 0.5)  # 最多扩展半个下落时间
            for ext in range(max_extend, 0, -50):
                if can_place(col, time, duration + ext):
                    duration += ext
                    break
            # 即使不能扩展，也要确保能放置原时长
            if can_place(col, time, duration):
                note_to_keep = {"time": time, "column": col, "type": ntype, "holdDuration": duration}
                if direction:
                    note_to_keep["direction"] = direction
                kept_notes.append(note_to_keep)
                # 更新 occupation_end（用扩展后的 duration）
                end_time = time + duration + MISS_WINDOW_MS
                if end_time > occupation_end.get(col, 0):
                    occupation_end[col] = end_time
            else:
                # 降级为 tap，但也需要检查 tap 能否放置
                if can_place(col, time, 0):
                    kept_notes.append(place(col, time, "tap", 0, None))
                # else: tap 也放不下，干脆丢弃
        elif can_place(col, time, 0):
            kept_notes.append(place(col, time, ntype, 0, direction))

    # 2. 在空隙处插入更多 tap
    if len(existing_notes) > 1:
        for i in range(len(existing_notes) - 1):
            n1 = existing_notes[i]
            n2 = existing_notes[i + 1]
            gap = n2["time"] - n1["time"]

            if gap > 700:  # 间隔够大，尝试插入
                mid_time = int((n1["time"] + n2["time"]) / 2)
                for col in range(column_count):
                    if can_place(col, mid_time, 0):
                        kept_notes.append(place(col, mid_time, "tap", 0, None))
                        break

    # 按时间排序
    kept_notes.sort(key=lambda x: x["time"])

    chart["notes"] = kept_notes
    out_path = output_path or input_path
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(chart, f, indent=2, ensure_ascii=False)

    print(f"Chart: {chart.get('name', 'Unknown')}")
    tap = sum(1 for n in kept_notes if n["type"] == "tap")
    hold = sum(1 for n in kept_notes if n["type"] == "hold")
    slide = sum(1 for n in kept_notes if n["type"] == "slide")
    print(f"  Total: {len(kept_notes)} notes | Tap: {tap}, Hold: {hold}, Slide: {slide}")
    avg_hold = sum(n.get("holdDuration", 0) for n in kept_notes if n["type"] == "hold")
    hold_count = hold
    if hold_count > 0:
        print(f"  Avg hold duration: {avg_hold // hold_count}ms")
    print(f"  Saved to: {out_path}")


def fix_chart(input_path, output_path=None):
    """修复现有乐谱 JSON，移除碰撞音符"""
    with open(input_path, 'r', encoding='utf-8') as f:
        chart = json.load(f)

    notes = chart.get("notes", [])
    column_count = 3
    drop_duration = chart.get("dropDuration", DEFAULT_DROP_DURATION)

    occupation_end = {}
    removed = []
    kept = []

    notes_sorted = sorted(notes, key=lambda x: x["time"])

    def can_place(col, time, duration=0):
        # collision window = [event_time, event_time + duration + MISS_WINDOW_MS]
        # 新音符的 event_time 必须 > 上一音符的 end_time（> 不是 >=，确保不重叠）
        return time > occupation_end.get(col, 0)

    def place(col, time, ntype, duration=0, direction=None):
        end_time = time + duration + MISS_WINDOW_MS
        note = {"time": time, "column": col, "type": ntype}
        if duration > 0:
            note["holdDuration"] = duration
        if direction:
            note["direction"] = direction
        kept.append(note)
        if end_time > occupation_end.get(col, 0):
            occupation_end[col] = end_time

    for n in notes_sorted:
        col = n["column"]
        time = n["time"]
        ntype = n["type"]
        duration = n.get("holdDuration", 0)
        direction = n.get("direction")

        if can_place(col, time, duration):
            place(col, time, ntype, duration, direction)
        else:
            removed.append(n)

    chart["notes"] = kept
    out_path = output_path or input_path
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(chart, f, indent=2, ensure_ascii=False)

    print(f"Chart: {chart.get('name', 'Unknown')}")
    print(f"  Kept: {len(kept)} notes, Removed: {len(removed)} conflicting notes")
    if removed:
        for n in removed[:5]:
            print(f"    REMOVED: col={n['column']} time={n['time']} type={n['type']}")
        if len(removed) > 5:
            print(f"    ... and {len(removed) - 5} more")
    print(f"  Saved to: {out_path}")


def main():
    parser = argparse.ArgumentParser(description="生成音游乐谱 v3")
    parser.add_argument("audio", help="音频文件路径 (m4a, mp3, wav) 或 JSON 乐谱路径 (用 --fix)")
    parser.add_argument("-o", "--output", help="输出JSON路径")
    parser.add_argument("--name", help="歌曲名称")
    parser.add_argument("--artist", help="艺术家名称")
    parser.add_argument("--intro", default="", help="简介")
    parser.add_argument("--fix", action="store_true", help="修复现有乐谱 JSON，移除碰撞音符")
    parser.add_argument("--rebuild", action="store_true", help="从现有乐谱重构，扩展 hold 时长并补充 tap/slide")

    args = parser.parse_args()

    audio_path = Path(args.audio)

    if args.fix:
        if not audio_path.exists():
            print(f"Error: File not found: {audio_path}")
            sys.exit(1)
        fix_chart(str(audio_path), args.output)
    elif args.rebuild:
        if not audio_path.exists():
            print(f"Error: File not found: {audio_path}")
            sys.exit(1)
        rebuild_chart(str(audio_path), args.output)
    else:
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
