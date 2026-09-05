#!/usr/bin/env python3
"""
音游打击音效生成器 — 合成 tap / slide / hold 三种不同音色的 WAV。

仅依赖 numpy + 标准库 wave。用法：

  python scripts/generate_line_sfx.py
  python scripts/generate_line_sfx.py -o assets/line/sfx
"""

from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 44100


def _fade(n: int, attack: float, release: float) -> np.ndarray:
    """线性 attack / release 包络，长度 n 采样。"""
    env = np.ones(n, dtype=np.float64)
    a = max(1, int(n * attack))
    r = max(1, int(n * release))
    env[:a] *= np.linspace(0.0, 1.0, a, endpoint=False)
    env[-r:] *= np.linspace(1.0, 0.0, r, endpoint=False)
    return env


def _exp_decay(n: int, tau_ms: float, sr: int = SAMPLE_RATE) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / sr
    return np.exp(-t / (tau_ms / 1000.0))


def _to_pcm16(samples: np.ndarray, peak: float = 0.85) -> np.ndarray:
    x = np.asarray(samples, dtype=np.float64)
    m = np.max(np.abs(x))
    if m > 1e-12:
        x = x / m * peak
    return np.clip(x * 32767.0, -32768, 32767).astype(np.int16)


def write_wav(path: Path, samples: np.ndarray, sr: int = SAMPLE_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = _to_pcm16(samples)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


# ---------------------------------------------------------------------------
# tap — 短促清脆点击（木块 + 高音叮）
# ---------------------------------------------------------------------------
def synth_tap(sr: int = SAMPLE_RATE) -> np.ndarray:
    duration = 0.09
    n = int(sr * duration)
    t = np.arange(n, dtype=np.float64) / sr

    # 主体：中高频短促正弦，指数衰减
    body = (
        0.7 * np.sin(2 * math.pi * 1850 * t)
        + 0.35 * np.sin(2 * math.pi * 3700 * t)
    ) * _exp_decay(n, tau_ms=28, sr=sr)

    # 瞬态：很短的噪声 burst，增加“敲击感”
    noise = np.random.default_rng(42).uniform(-1.0, 1.0, n)
    click = noise * _exp_decay(n, tau_ms=6, sr=sr) * 0.45

    # 低频垫底，避免过于尖锐
    thud = 0.25 * np.sin(2 * math.pi * 220 * t) * _exp_decay(n, tau_ms=40, sr=sr)

    out = (body + click + thud) * _fade(n, attack=0.01, release=0.25)
    return out


# ---------------------------------------------------------------------------
# slide — 空气感扫音（噪声 whoosh + 频率扫频）
# ---------------------------------------------------------------------------
def synth_slide(sr: int = SAMPLE_RATE) -> np.ndarray:
    duration = 0.22
    n = int(sr * duration)
    t = np.arange(n, dtype=np.float64) / sr
    rng = np.random.default_rng(7)

    # 上升扫频：像手指划过
    f0, f1 = 420.0, 2400.0
    phase = 2 * math.pi * (f0 * t + (f1 - f0) * t * t / (2 * duration))
    chirp = 0.35 * np.sin(phase)

    # 带通式噪声 whoosh：用积分噪声做简单高通后再包络
    white = rng.normal(0.0, 1.0, n)
    # 一阶差分 ≈ 高通，再平滑一点
    whoosh = np.diff(white, prepend=white[0])
    whoosh = np.convolve(whoosh, np.ones(32) / 32.0, mode="same")
    # 中心能量在中段偏前
    whoosh_env = np.sin(math.pi * np.clip(t / duration, 0, 1)) ** 1.4
    whoosh = whoosh / (np.max(np.abs(whoosh)) + 1e-12) * whoosh_env * 0.55

    # 轻微谐波扫频，增加“滑轨”质感
    f2 = 800.0 + 1600.0 * (t / duration)
    shimmer = 0.18 * np.sin(2 * math.pi * np.cumsum(f2) / sr)

    out = (chirp + whoosh + shimmer) * _fade(n, attack=0.08, release=0.35)
    return out


# ---------------------------------------------------------------------------
# hold — 柔和起音 + 可感知持续感（双音 pad）
# ---------------------------------------------------------------------------
def synth_hold(sr: int = SAMPLE_RATE) -> np.ndarray:
    duration = 0.45
    n = int(sr * duration)
    t = np.arange(n, dtype=np.float64) / sr

    # 根音 + 五度，温暖持续
    root = 0.45 * np.sin(2 * math.pi * 392.0 * t)  # G4
    fifth = 0.28 * np.sin(2 * math.pi * 587.33 * t)  # D5
    octave = 0.12 * np.sin(2 * math.pi * 784.0 * t)  # G5

    # 轻微振幅颤音，避免死板
    vibrato = 1.0 + 0.04 * np.sin(2 * math.pi * 5.5 * t)
    pad = (root + fifth + octave) * vibrato

    # 起音叮：短高音提示“按住了”
    attack_n = int(sr * 0.08)
    attack_t = t[:attack_n]
    ding = np.zeros(n, dtype=np.float64)
    ding[:attack_n] = (
        0.4 * np.sin(2 * math.pi * 1568 * attack_t) * _exp_decay(attack_n, tau_ms=55, sr=sr)
    )

    # 慢起快收：适合作为 hold 开始音；尾部淡出避免爆音
    env = _fade(n, attack=0.12, release=0.4)
    # 中段保持电平
    sustain = np.ones(n, dtype=np.float64)
    sustain[-int(n * 0.35) :] *= np.linspace(1.0, 0.15, int(n * 0.35), endpoint=False)
    out = (pad * env * sustain + ding) * _fade(n, attack=0.02, release=0.15)
    return out


GENERATORS = {
    "tap": synth_tap,
    "slide": synth_slide,
    "hold": synth_hold,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="生成音游 tap/slide/hold 打击音效 WAV")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("assets/line/sfx"),
        help="输出目录（默认 assets/line/sfx）",
    )
    parser.add_argument(
        "--sr",
        type=int,
        default=SAMPLE_RATE,
        help=f"采样率（默认 {SAMPLE_RATE}）",
    )
    args = parser.parse_args()

    out_dir: Path = args.output
    out_dir.mkdir(parents=True, exist_ok=True)

    for name, gen in GENERATORS.items():
        samples = gen(sr=args.sr)
        path = out_dir / f"{name}.wav"
        write_wav(path, samples, sr=args.sr)
        ms = len(samples) / args.sr * 1000
        print(f"  wrote {path}  ({ms:.0f} ms, {args.sr} Hz)")

    print(f"done → {out_dir.resolve()}")


if __name__ == "__main__":
    main()
