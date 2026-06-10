#!/usr/bin/env python3
"""
Phase 10 vectors — High profile I-frames (Intra_8x8 + 8x8 transform).

Smooth gradients push x264 towards transform_size_8x8_flag=1; each case
prints its 8x8-intra percentage and the generator asserts the corpus as a
whole actually exercises the 8x8 path. Covers CABAC and CAVLC entropies,
deblock on/off, qp sweep and non-MB-aligned sizes.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase10"


def synth(w: int, h: int, pat: str, seed: int = 3):
    rng = np.random.default_rng(seed)
    cw, ch = w // 2, h // 2
    if pat == "grad":
        y = (np.add.outer(np.linspace(20, 230, h), np.linspace(0, 20, w))
             ).clip(0, 255).astype(np.uint8)
        u = np.broadcast_to(np.linspace(60, 200, cw)[None, :], (ch, cw)).astype(np.uint8)
        v = np.broadcast_to(np.linspace(200, 60, ch)[:, None], (ch, cw)).astype(np.uint8)
    elif pat == "smooth":
        xx, yy = np.meshgrid(np.linspace(0, 6.0, w), np.linspace(0, 4.0, h))
        y = (128 + 90 * np.sin(xx) * np.cos(yy * 0.7)).clip(0, 255).astype(np.uint8)
        cxx, cyy = np.meshgrid(np.linspace(0, 3.0, cw), np.linspace(0, 2.0, ch))
        u = (128 + 70 * np.sin(cxx + 1)).clip(0, 255).astype(np.uint8)
        v = (128 + 70 * np.cos(cyy)).clip(0, 255).astype(np.uint8)
    elif pat == "check":
        c = (np.add.outer(np.arange(h) // 16, np.arange(w) // 16) % 2 == 0)
        y = np.where(c, 200, 60).astype(np.uint8)
        cc = (np.add.outer(np.arange(ch) // 8, np.arange(cw) // 8) % 2 == 0)
        u = np.where(cc, 90, 160).astype(np.uint8)
        v = np.where(cc, 150, 100).astype(np.uint8)
    else:  # noise
        y = rng.integers(0, 256, (h, w), dtype=np.uint8).astype(np.uint8)
        u = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
        v = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
    return y.tobytes() + u.tobytes() + v.tobytes()


CASES = [
    # (w, h, pattern, qp, cavlc, nodeblock)
    (64,  64,  "grad",   30, 0, 1),
    (64,  64,  "grad",   30, 1, 1),
    (64,  64,  "smooth", 26, 0, 0),
    (64,  64,  "smooth", 26, 1, 0),
    (128, 96,  "smooth", 32, 0, 1),
    (128, 96,  "smooth", 32, 1, 1),
    (160, 128, "grad",   38, 0, 0),
    (160, 128, "grad",   38, 1, 0),
    (320, 240, "smooth", 30, 0, 0),
    (320, 240, "smooth", 30, 1, 1),
    (100, 76,  "smooth", 28, 0, 0),
    (100, 76,  "smooth", 28, 1, 1),
    (322, 242, "grad",   34, 0, 0),
    (34,  18,  "grad",   26, 0, 1),
    (64,  64,  "check",  40, 0, 0),
    (64,  64,  "noise",  46, 0, 0),
    (96,  96,  "smooth", 12, 0, 1),
    (96,  96,  "smooth", 50, 0, 0),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    pct_sum = 0.0
    for w, h, pat, qp, cavlc, nodb in CASES:
        tmp.write_bytes(synth(w, h, pat))
        ent = "cavlc" if cavlc else "cabac"
        name = f"p10_{pat}_{w}x{h}_q{qp}_{ent}{'_nodb' if nodb else ''}"
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--profile", "high", "--qp", str(qp), "--slices", "1",
               "--frames", "1", "--input-res", f"{w}x{h}", "--input-csp",
               "i420", "--fps", "25", "-v"]
        if cavlc: cmd.append("--no-cabac")
        if nodb: cmd.append("--no-deblock")
        cmd += ["-o", str(b264), str(tmp)]
        r = subprocess.run(cmd, check=True, capture_output=True, text=True)
        m = re.search(r"8x8 transform intra:\s*([\d.]+)%", r.stderr + r.stdout)
        pct = float(m.group(1)) if m else 0.0
        pct_sum += pct
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt",
                        "yuv420p", str(OUT / (name + ".yuv"))], check=True)
        print(f"[gen] {name}  8x8={pct:.0f}%")
        n += 1
    tmp.unlink(missing_ok=True)
    avg = pct_sum / n
    print(f"generated {n} Phase 10 vectors, mean 8x8-intra {avg:.0f}%")
    if avg < 20:
        print("WARNING: corpus barely exercises the 8x8 path", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
