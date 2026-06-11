#!/usr/bin/env python3
"""
Phase 16 vectors — explicit weighted prediction (--weightp 1) and
high-profile inter 8x8 transforms.

Fades give x264 a constant luma ratio between frames, so it emits real
pred_weight_table entries; the generator parses 'Weighted P-Frames'
stats and asserts a nonzero share. High-profile cases additionally
exercise transform_size_8x8_flag on inter MBs (both entropies).
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase16"


def gen_fade(w, h, n, kind, seed=5):
    rng = np.random.default_rng(seed)
    cw, ch = w // 2, h // 2
    if kind == "noise":
        base = rng.integers(40, 200, (h, w), dtype=np.uint8).astype(np.int16)
    else:
        base = (np.add.outer(np.linspace(40, 200, h), np.linspace(0, 30, w))
                ).astype(np.int16)
    bu = rng.integers(60, 180, (ch, cw), dtype=np.uint8).astype(np.int16)
    bv = rng.integers(60, 180, (ch, cw), dtype=np.uint8).astype(np.int16)
    frames = []
    for f in range(n):
        fade = 1.0 - f * 0.16
        y = (base * fade).clip(0, 255).astype(np.uint8)
        u = ((bu - 128) * fade + 128).clip(0, 255).astype(np.uint8)
        v = ((bv - 128) * fade + 128).clip(0, 255).astype(np.uint8)
        frames.append(np.roll(y, f, axis=1).tobytes() +
                      u.tobytes() + v.tobytes())
    return b"".join(frames)


CASES = [
    # (w, h, nframes, kind, qp, profile, nref, cavlc)
    (64,  64,  5, "noise", 24, "baseline", 1, 1),
    (64,  64,  5, "noise", 24, "main",     1, 0),
    (64,  64,  5, "noise", 24, "high",     1, 0),
    (64,  64,  5, "noise", 24, "high",     1, 1),
    (100, 76,  5, "grad",  26, "high",     2, 0),
    (160, 128, 5, "noise", 30, "high",     2, 1),
    (320, 240, 4, "grad",  28, "high",     1, 0),
    (96,  96,  6, "noise", 20, "main",     2, 0),
    (322, 242, 4, "grad",  32, "high",     2, 0),
    (34,  18,  5, "noise", 26, "baseline", 2, 1),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    for w, h, nf, kind, qp, prof, nref, cavlc in CASES:
        tmp.write_bytes(gen_fade(w, h, nf, kind))
        name = (f"p16_{kind}_{w}x{h}_n{nf}_q{qp}_{prof}_r{nref}"
                f"{'_cavlc' if cavlc else ''}")
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--profile", prof, "--qp", str(qp),
               "--frames", str(nf), "--ref", str(nref), "--weightp", "1",
               "--slices", "1", "--input-res", f"{w}x{h}",
               "--input-csp", "i420", "--fps", "25"]
        if prof != "baseline":
            cmd += ["--bframes", "0"]
        if cavlc:
            cmd.append("--no-cabac")
        cmd += ["-o", str(b264), str(tmp)]
        r = subprocess.run(cmd, check=True, capture_output=True, text=True)
        if prof == "baseline":
            wy = -1.0                  # baseline forbids WP; t8/ref path only
        else:
            m = re.search(r"Weighted P-Frames: Y:([\d.]+)%", r.stderr)
            assert m, f"{name}: no weighted stats"
            wy = float(m.group(1))
            assert wy > 0.0, (
                f"{name}: 0% weighted P frames — vector would not exercise "
                f"weighted prediction; fix the content")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt",
                        "yuv420p", str(OUT / (name + ".yuv"))], check=True)
        n += 1
        print(f"  {name}: weighted Y {wy:.0f}%")
    tmp.unlink(missing_ok=True)
    print(f"generated {n} Phase 16 vectors (+golden yuv) under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
