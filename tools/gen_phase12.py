#!/usr/bin/env python3
"""
Phase 12 vectors — multi-slice I-frames.

Same pipeline; x264 --slices N splits the frame into row bands.
Covers 2..8 slices, CABAC and CAVLC, high profile (8x8 across slice
boundaries), deblock on (cross-slice filtering, idc=0) and off, and
non-MB-aligned sizes. Slice-boundary neighbor availability is the
device under test.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase12"


def synth(w: int, h: int, pat: str, seed: int = 3):
    rng = np.random.default_rng(seed)
    cw, ch = w // 2, h // 2
    if pat == "grad":
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


CASES = [
    # (w, h, pattern, qp, nslices, profile, cavlc, deblock-off)
    (64,  64,  "grad",  28, 2, "main", 0, 0),
    (64,  64,  "noise", 24, 2, "main", 1, 0),
    (144, 96,  "check", 26, 3, "main", 0, 0),
    (144, 96,  "grad",  30, 3, "main", 1, 1),
    (320, 240, "grad",  28, 4, "high", 0, 0),
    (320, 240, "noise", 34, 4, "main", 0, 1),
    (320, 240, "grad",  30, 8, "high", 0, 0),
    (160, 128, "smoothish", 32, 4, "high", 0, 0),
    (160, 128, "smoothish", 32, 4, "high", 1, 0),
    (100, 76,  "grad",  28, 2, "high", 0, 0),
    (322, 242, "check", 32, 5, "main", 0, 0),
    (128, 128, "noise", 40, 6, "main", 0, 0),
    (64,  128, "grad",  20, 4, "main", 1, 0),
    (96,  96,  "noise", 12, 3, "high", 0, 1),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    for w, h, pat, qp, ns, prof, cavlc, nodb in CASES:
        tmp.write_bytes(synth(w, h, "grad" if pat == "smoothish" else pat))
        name = (f"p12_{pat}_{w}x{h}_q{qp}_s{ns}_{prof}"
                f"{'_cavlc' if cavlc else ''}{'_nodb' if nodb else ''}")
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--profile", prof, "--qp", str(qp),
               "--slices", str(ns),
               "--frames", "1", "--input-res", f"{w}x{h}", "--input-csp", "i420",
               "--fps", "25"]
        if cavlc:
            cmd += ["--no-cabac"]
        if nodb:
            cmd += ["--no-deblock"]
        cmd += ["-o", str(b264), str(tmp)]
        subprocess.run(cmd, check=True, capture_output=True)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt", "yuv420p",
                        str(OUT / (name + ".yuv"))], check=True)
        n += 1
    tmp.unlink(missing_ok=True)
    print(f"generated {n} Phase 12 vectors (+golden yuv) under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
