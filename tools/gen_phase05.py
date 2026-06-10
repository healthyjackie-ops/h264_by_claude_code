#!/usr/bin/env python3
"""
Phase 5 vectors — single-IDR I-frame, Baseline/CAVLC, deblocking OFF.

Patterns are synthesized directly in the YUV domain (H.264 codes YUV
planes; no RGB conversion ambiguity). Each case is encoded with x264
(--profile baseline --no-deblock --slices 1) and decoded with ffmpeg to a
sibling .yuv golden that golden_compare byte-compares against.

Deblocking-ON streams are Phase 6 (verification/vectors/phase06).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase05"


def synth(w: int, h: int, pat: str, seed: int = 3):
    rng = np.random.default_rng(seed)
    cw, ch = w // 2, h // 2
    if pat == "flat":
        y = np.full((h, w), 128, np.uint8)
        u = np.full((ch, cw), 110, np.uint8)
        v = np.full((ch, cw), 150, np.uint8)
    elif pat == "grad":
        y = (np.add.outer(np.linspace(20, 230, h), np.linspace(0, 20, w))
             ).clip(0, 255).astype(np.uint8)
        u = np.broadcast_to(np.linspace(60, 200, cw)[None, :], (ch, cw)).astype(np.uint8)
        v = np.broadcast_to(np.linspace(200, 60, ch)[:, None], (ch, cw)).astype(np.uint8)
    elif pat == "check":
        c = (np.add.outer(np.arange(h) // 8, np.arange(w) // 8) % 2 == 0)
        y = np.where(c, 210, 40).astype(np.uint8)
        cc = (np.add.outer(np.arange(ch) // 4, np.arange(cw) // 4) % 2 == 0)
        u = np.where(cc, 80, 170).astype(np.uint8)
        v = np.where(cc, 160, 90).astype(np.uint8)
    else:  # noise
        y = rng.integers(0, 256, (h, w), dtype=np.uint8).astype(np.uint8)
        u = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
        v = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
    return y.tobytes() + u.tobytes() + v.tobytes()


def encode(yuv: Path, out264: Path, w: int, h: int, qp: int,
           extra: list[str]) -> None:
    cmd = ["x264", "--profile", "baseline", "--qp", str(qp), "--slices", "1",
           "--frames", "1", "--input-res", f"{w}x{h}", "--input-csp", "i420",
           "--fps", "25", "--no-deblock"] + extra + ["-o", str(out264), str(yuv)]
    subprocess.run(cmd, check=True, capture_output=True)


def golden(in264: Path, outyuv: Path) -> None:
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", str(in264), "-f", "rawvideo", "-pix_fmt", "yuv420p",
                    str(outyuv)], check=True)


CASES = [
    # (w, h, pattern, qp, extra x264 args)
    (16,  16,  "flat",  30, []),
    (16,  16,  "grad",  24, []),
    (32,  32,  "grad",  30, []),
    (32,  32,  "noise", 18, []),
    (48,  32,  "check", 26, []),
    (64,  64,  "grad",  38, []),
    (64,  64,  "noise", 32, []),
    (64,  64,  "check", 44, []),
    (96,  64,  "grad",  10, []),
    (144, 96,  "check", 20, []),
    (320, 240, "grad",  26, []),
    (320, 240, "noise", 36, []),
    # non-MB-aligned (SPS cropping)
    (18,  16,  "check", 30, []),
    (100, 76,  "grad",  28, []),
    (100, 76,  "noise", 24, []),
    (322, 242, "grad",  30, []),
    (34,  18,  "noise", 22, []),
    # qp extremes
    (64,  48,  "grad",  4,  []),
    (64,  48,  "noise", 51, []),
    # PCM-heavy: near-lossless noise makes x264 pick I_PCM macroblocks
    (48,  48,  "noise", 2,  []),
    # intra tuning variants
    (128, 96,  "grad",  26, ["--no-8x8dct"]),
    (160, 128, "check", 32, []),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    for w, h, pat, qp, extra in CASES:
        tmp.write_bytes(synth(w, h, pat))
        name = f"p05_{pat}_{w}x{h}_q{qp}"
        b264 = OUT / (name + ".264")
        encode(tmp, b264, w, h, qp, extra)
        golden(b264, OUT / (name + ".yuv"))
        n += 1
    tmp.unlink(missing_ok=True)
    print(f"generated {n} Phase 5 vectors (+golden yuv) under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
