#!/usr/bin/env python3
"""
Phase 8 vectors — CABAC I-frames (x264 main profile).

Same synthesis/golden pipeline as gen_phase05/06; encoded with
--profile main so entropy_coding_mode=1. Covers I_4x4-heavy noise,
I_16x16-heavy gradients, deblock on/off, qp extremes and non-MB-aligned
sizes — every CABAC syntax path against the ffmpeg golden.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase08"


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
    # (w, h, pattern, qp, deblock "a:b", None = default, "off" = --no-deblock)
    (16,  16,  "grad",  30, "off"),
    (16,  16,  "noise", 30, "off"),
    (32,  32,  "grad",  30, "off"),
    (32,  32,  "noise", 18, "off"),
    (48,  32,  "check", 26, "off"),
    (64,  64,  "noise", 20, "off"),
    (64,  64,  "grad",  38, None),
    (64,  64,  "check", 46, None),
    (96,  64,  "grad",  8,  None),
    (144, 96,  "check", 24, None),
    (320, 240, "noise", 36, None),
    (320, 240, "grad",  28, None),
    (100, 76,  "grad",  28, "off"),
    (322, 242, "grad",  32, None),
    (34,  18,  "noise", 24, "off"),
    (64,  48,  "noise", 51, "off"),
    (64,  48,  "grad",  4,  None),
    (64,  64,  "check", 30, "3:3"),
    (100, 76,  "grad",  34, "-6:6"),
    (128, 128, "noise", 30, None),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    for w, h, pat, qp, db in CASES:
        tmp.write_bytes(synth(w, h, pat))
        tag = "d0" if db is None else ("nodb" if db == "off"
                                        else "d" + db.replace(":", "_").replace("-", "m"))
        name = f"p08_{pat}_{w}x{h}_q{qp}_{tag}"
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--profile", "main", "--qp", str(qp), "--slices", "1",
               "--frames", "1", "--input-res", f"{w}x{h}", "--input-csp", "i420",
               "--fps", "25"]
        if db == "off":
            cmd += ["--no-deblock"]
        elif db is not None:
            cmd += ["--deblock", db]
        cmd += ["-o", str(b264), str(tmp)]
        subprocess.run(cmd, check=True, capture_output=True)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt", "yuv420p",
                        str(OUT / (name + ".yuv"))], check=True)
        n += 1
    tmp.unlink(missing_ok=True)
    print(f"generated {n} Phase 8 vectors (+golden yuv) under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
