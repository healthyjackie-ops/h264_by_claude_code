#!/usr/bin/env python3
"""
Phase 6 vectors — deblocking filter ON (x264 defaults + offset sweeps).

Same synthesis/golden pipeline as gen_phase05.py; the only change is the
loop filter: default --deblock 0:0 plus alpha/beta offset variants, which
exercise bS=4 MB edges, bS=3 internal edges, strong/normal filter
selection and the chroma path against ffmpeg.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase06"


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
    # (w, h, pattern, qp, deblock "a:b" or None for default)
    (16,  16,  "grad",  30, None),
    (32,  32,  "check", 26, None),
    (32,  32,  "noise", 20, None),
    (64,  64,  "grad",  38, None),
    (64,  64,  "noise", 32, None),
    (64,  64,  "check", 46, None),     # high qp: strong filtering everywhere
    (96,  64,  "grad",  12, None),
    (144, 96,  "check", 24, None),
    (320, 240, "grad",  28, None),
    (320, 240, "noise", 40, None),
    (100, 76,  "grad",  30, None),     # non-aligned + cropping
    (322, 242, "check", 34, None),
    (34,  18,  "noise", 26, None),
    # explicit alpha/beta offsets (slice header a_off/b_off paths)
    (64,  64,  "check", 30, "3:3"),
    (64,  64,  "check", 30, "-3:-3"),
    (100, 76,  "grad",  34, "6:-6"),
    (144, 96,  "noise", 28, "-6:6"),
    (320, 240, "grad",  36, "2:-2"),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    for w, h, pat, qp, db in CASES:
        tmp.write_bytes(synth(w, h, pat))
        tag = "d0" if db is None else "d" + db.replace(":", "_").replace("-", "m")
        name = f"p06_{pat}_{w}x{h}_q{qp}_{tag}"
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--profile", "baseline", "--qp", str(qp), "--slices", "1",
               "--frames", "1", "--input-res", f"{w}x{h}", "--input-csp", "i420",
               "--fps", "25"]
        if db is not None:
            cmd += ["--deblock", db]
        cmd += ["-o", str(b264), str(tmp)]
        subprocess.run(cmd, check=True, capture_output=True)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt", "yuv420p",
                        str(OUT / (name + ".yuv"))], check=True)
        n += 1
    tmp.unlink(missing_ok=True)
    print(f"generated {n} Phase 6 vectors (+golden yuv) under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
