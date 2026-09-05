#!/usr/bin/env python3
"""
音游打击音效生成器 — 基于真实采样（非合成）。

为什么不用纯合成：简单方波/噪底很难做出 Phigros 那种采样质感。
本脚本从 Sonic Pi 官方样本库拉取 CC0 真实镲片/刮碟采样，裁剪、淡出、归一化后写出：

  tap   ← 闭镲 one-shot（脆「哧」）
  slide ← vinyl scratch（打碟「唰」）
  hold  ← 短开镲/金属镲（持续「嘶」）

许可：Creative Commons Zero（可商用、可再分发，无需署名）。
来源：https://github.com/sonic-pi-net/sonic-pi/tree/main/etc/samples
原 Freesound 链接见该目录 README。

依赖：numpy + soundfile（pip install soundfile）

  python scripts/generate_line_sfx.py
  python scripts/generate_line_sfx.py --offline   # 只用本地缓存，不联网
"""

from __future__ import annotations

import argparse
import urllib.request
import wave
from pathlib import Path

import numpy as np

try:
    import soundfile as sf
except ImportError as e:  # pragma: no cover
    raise SystemExit(
        "需要 soundfile：pip install soundfile\n" + str(e)
    ) from e

SAMPLE_RATE = 44100
SONIC_PI_RAW = (
    "https://raw.githubusercontent.com/sonic-pi-net/sonic-pi/main/etc/samples"
)

# 角色 → 源文件（CC0）
SOURCES = {
    "tap": "drum_cymbal_closed.flac",  # 经典闭镲，短脆
    "slide": "vinyl_scratch.flac",  # 打碟刮擦
    "hold": "hat_zild.flac",  # 金属镲短持续
}

# 各角色目标时长 / 淡出
SHAPE = {
    "tap": dict(max_ms=70, fade_ms=18, peak=0.82, gain=1.15),
    "slide": dict(max_ms=160, fade_ms=40, peak=0.78, gain=1.0),
    "hold": dict(max_ms=260, fade_ms=70, peak=0.76, gain=1.05),
}


def _cache_dir(root: Path) -> Path:
    d = root / ".tmp" / "line_sfx_src"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _download(name: str, cache: Path, offline: bool) -> Path:
    dest = cache / name
    if dest.exists() and dest.stat().st_size > 0:
        return dest
    if offline:
        raise FileNotFoundError(f"离线模式缺少缓存: {dest}")
    url = f"{SONIC_PI_RAW}/{name}"
    print(f"  download {name} …")
    urllib.request.urlretrieve(url, dest)
    return dest


def _to_mono(data: np.ndarray) -> np.ndarray:
    x = np.asarray(data, dtype=np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    return x


def _resample_linear(x: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    if sr_in == sr_out:
        return x
    n_out = int(round(len(x) * sr_out / sr_in))
    t_in = np.linspace(0.0, 1.0, num=len(x), endpoint=False)
    t_out = np.linspace(0.0, 1.0, num=n_out, endpoint=False)
    return np.interp(t_out, t_in, x).astype(np.float64)


def _trim_silence(x: np.ndarray, thr: float = 0.008) -> np.ndarray:
    absx = np.abs(x)
    idx = np.where(absx > thr)[0]
    if len(idx) == 0:
        return x
    start = max(0, int(idx[0]) - 8)
    end = min(len(x), int(idx[-1]) + 32)
    return x[start:end]


def _shape(
    x: np.ndarray,
    sr: int,
    *,
    max_ms: float,
    fade_ms: float,
    peak: float,
    gain: float,
) -> np.ndarray:
    x = _trim_silence(x * gain)
    max_n = int(sr * max_ms / 1000.0)
    if len(x) > max_n:
        x = x[:max_n].copy()

    fade_n = min(len(x), int(sr * fade_ms / 1000.0))
    if fade_n > 1:
        x[-fade_n:] *= np.linspace(1.0, 0.0, fade_n, endpoint=True) ** 1.35

    # 起音微抬，增加「脆」
    atk = min(len(x), int(sr * 0.002))
    if atk > 1:
        x[:atk] *= np.linspace(0.55, 1.0, atk, endpoint=False)

    m = np.max(np.abs(x))
    if m > 1e-12:
        x = x / m * peak
    return x.astype(np.float64)


def _write_wav(path: Path, samples: np.ndarray, sr: int = SAMPLE_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def _write_attribution(out_dir: Path) -> None:
    text = """# Line SFX 来源说明

本目录 wav 由 `scripts/generate_line_sfx.py` 从 Sonic Pi 样本库裁剪生成。

- 许可：Creative Commons Zero (CC0)
- 上游：https://github.com/sonic-pi-net/sonic-pi/tree/main/etc/samples
- 映射：
  - tap.wav   ← drum_cymbal_closed.flac
  - slide.wav ← vinyl_scratch.flac
  - hold.wav  ← hat_zild.flac

Phigros 等商业音游音效受版权保护，不可直接使用；本方案用公开域真实采样逼近「脆镲 / 打碟」手感。
"""
    (out_dir / "SOURCES.md").write_text(text, encoding="utf-8")


def build_one(role: str, cache: Path, offline: bool) -> np.ndarray:
    src_name = SOURCES[role]
    path = _download(src_name, cache, offline=offline)
    data, sr = sf.read(str(path), always_2d=False)
    x = _to_mono(data)
    x = _resample_linear(x, int(sr), SAMPLE_RATE)
    return _shape(x, SAMPLE_RATE, **SHAPE[role])


def main() -> None:
    parser = argparse.ArgumentParser(description="从 CC0 真实采样生成 line 打击音效")
    parser.add_argument("-o", "--output", type=Path, default=Path("assets/line/sfx"))
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="仓库根（用于 .tmp 缓存）",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="不联网，只用 .tmp/line_sfx_src 缓存",
    )
    args = parser.parse_args()

    cache = _cache_dir(args.repo_root)
    out_dir: Path = args.output
    out_dir.mkdir(parents=True, exist_ok=True)

    for role in ("tap", "slide", "hold"):
        samples = build_one(role, cache, offline=args.offline)
        path = out_dir / f"{role}.wav"
        _write_wav(path, samples)
        print(
            f"  wrote {path}  ({len(samples) / SAMPLE_RATE * 1000:.0f} ms)"
            f"  ← {SOURCES[role]}"
        )

    _write_attribution(out_dir)
    print(f"done → {out_dir.resolve()}")
    print("提示：完整重启 app 才能刷新 asset 缓存。")


if __name__ == "__main__":
    main()
