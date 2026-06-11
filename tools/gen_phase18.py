#!/usr/bin/env python3
"""
Phase 18 vectors — x264 DEFAULTS: no compatibility pins at all.

High profile, CABAC, B-pyramid (reference B frames), implicit weighted
bipred (weightb), weightp 2 (duplicate-ref list modification), 8x8
transforms, multiple references — whatever x264 picks by default. Fades
push weightp/weightb activity; oscillating motion pushes multi-ref.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase18"


def gen(w, h, n, kind, seed=11):
    rng = np.random.default_rng(seed)
    cw, ch = w // 2, h // 2
    if kind == "noise":
        base = rng.integers(0, 256, (h, w), dtype=np.uint8).astype(np.int16)
    else:
        base = (np.add.outer(np.linspace(20, 230, h), np.linspace(0, 30, w))
                ).astype(np.int16)
    bu = rng.integers(60, 200, (ch, cw), dtype=np.uint8).astype(np.int16)
    bv = rng.integers(60, 200, (ch, cw), dtype=np.uint8).astype(np.int16)
    frames = []
    for f in range(n):
        if kind == "fade":
            fade = 1.0 - f * 0.10
            y = (base * fade).clip(0, 255).astype(np.uint8)
            u = ((bu - 128) * fade + 128).clip(0, 255).astype(np.uint8)
            v = ((bv - 128) * fade + 128).clip(0, 255).astype(np.uint8)
            y = np.roll(y, f, axis=1)
        else:
            sh = [0, 3, 1][f % 3]
            y = np.roll(base.clip(0, 255).astype(np.uint8), sh, axis=1)
            y = np.roll(y, (f * 2) % 5, axis=0)
            u = np.roll(bu.astype(np.uint8), sh // 2, axis=1)
            v = np.roll(bv.astype(np.uint8), sh // 2, axis=1)
        frames.append(y.tobytes() + u.tobytes() + v.tobytes())
    return b"".join(frames)


CASES = [
    # (w, h, nframes, kind, qp, extra)
    (320, 240, 10, "grad",  26, []),
    (320, 240, 10, "noise", 30, []),
    (320, 240, 10, "fade",  26, []),
    (160, 128, 12, "fade",  24, []),
    (100, 76,  10, "grad",  28, []),
    (322, 242, 10, "noise", 32, []),
    (96,  96,  12, "fade",  20, ["--no-cabac"]),
    (64,  64,  12, "noise", 26, ["--no-cabac"]),
    (640, 480, 8,  "grad",  28, []),
    (160, 128, 12, "noise", 40, ["--slices", "2"]),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    for w, h, nf, kind, qp, extra in CASES:
        tmp.write_bytes(gen(w, h, nf, kind))
        tag = "_".join(x.lstrip("-") for x in extra) if extra else "def"
        name = f"p18_{kind}_{w}x{h}_n{nf}_q{qp}_{tag}"
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--qp", str(qp), "--frames", str(nf),
               "--input-res", f"{w}x{h}", "--input-csp", "i420",
               "--fps", "25"] + extra + ["-o", str(b264), str(tmp)]
        subprocess.run(cmd, check=True, capture_output=True)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt",
                        "yuv420p", str(OUT / (name + ".yuv"))], check=True)
        n += 1
    tmp.unlink(missing_ok=True)
    print(f"generated {n} Phase 18 vectors (+golden yuv) under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
