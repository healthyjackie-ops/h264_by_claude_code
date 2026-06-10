#!/usr/bin/env python3
"""
Phase 15 vectors — multi-reference P frames (--ref 2/3).

Oscillating translation makes even frames match the frame TWO back, so
x264 genuinely uses ref_idx > 0 (the generator parses x264's "ref P L0"
stats and asserts a nonzero share — a vector that never leaves ref0
would validate nothing). Both entropies; main adds --bframes 0
--weightp 0 to stay in I/P single-list scope.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase15"


def gen_osc(w, h, n, kind, seed=9):
    rng = np.random.default_rng(seed)
    cw, ch = w // 2, h // 2
    if kind == "noise":
        base = rng.integers(0, 256, (h, w), dtype=np.uint8).astype(np.uint8)
    else:
        base = (np.add.outer(np.linspace(20, 230, h), np.linspace(0, 40, w))
                ).clip(0, 255).astype(np.uint8)
    bu = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
    bv = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
    frames = []
    for f in range(n):
        sh = [0, 3, 1][f % 3] if kind == "noise" else [0, 3][f % 2]
        y = np.roll(base, sh, axis=1)
        u = np.roll(bu, sh // 2, axis=1)
        v = np.roll(bv, sh // 2, axis=1)
        frames.append(y.tobytes() + u.tobytes() + v.tobytes())
    return b"".join(frames)


CASES = [
    # (w, h, nframes, kind, qp, profile, nref, deblock-off)
    (64,  64,  6, "noise", 26, "baseline", 2, 0),
    (64,  64,  6, "noise", 26, "baseline", 3, 0),
    (64,  64,  6, "noise", 26, "main",     2, 0),
    (64,  64,  6, "noise", 26, "main",     3, 0),
    (100, 76,  6, "grad",  28, "baseline", 2, 1),
    (100, 76,  6, "grad",  28, "main",     2, 1),
    (160, 128, 6, "noise", 32, "main",     3, 0),
    (320, 240, 5, "noise", 30, "baseline", 3, 0),
    (322, 242, 5, "grad",  30, "main",     2, 0),
    (96,  96,  8, "noise", 20, "main",     3, 0),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    for w, h, nf, kind, qp, prof, nref, nodb in CASES:
        tmp.write_bytes(gen_osc(w, h, nf, kind))
        name = (f"p15_{kind}_{w}x{h}_n{nf}_q{qp}_{prof}_r{nref}"
                f"{'_nodb' if nodb else ''}")
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--profile", prof, "--qp", str(qp),
               "--frames", str(nf), "--ref", str(nref), "--slices", "1",
               "--input-res", f"{w}x{h}", "--input-csp", "i420",
               "--fps", "25"]
        if prof != "baseline":
            cmd += ["--bframes", "0", "--weightp", "0"]
        if nodb:
            cmd.append("--no-deblock")
        cmd += ["-o", str(b264), str(tmp)]
        r = subprocess.run(cmd, check=True, capture_output=True, text=True)
        m = re.search(r"ref P L0: ([\d.% ]+)", r.stderr)
        assert m, "no ref stats from x264"
        shares = [float(x.rstrip("%")) for x in m.group(1).split()]
        beyond0 = sum(shares[1:])
        assert beyond0 >= 10.0, (
            f"{name}: ref>0 share only {beyond0:.1f}% — vector would not "
            f"exercise multi-reference; fix the content")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt",
                        "yuv420p", str(OUT / (name + ".yuv"))], check=True)
        n += 1
        print(f"  {name}: ref>0 {beyond0:.0f}%")
    tmp.unlink(missing_ok=True)
    print(f"generated {n} Phase 15 vectors (+golden yuv) under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
