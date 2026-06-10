#!/usr/bin/env python3
"""
Phase 11 vectors — scaling lists (non-flat CQM).

Two encoder paths exercise both decoder paths:
  --cqm jvt      : all PPS lists absent -> fall-back rule A defaults
  --cqmfile FILE : explicit lists       -> delta_scale chain parsing
across CABAC/CAVLC, 8x8 on/off, deblock on/off.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase11"

CQMFILE = """INTRA4X4_LUMA =
 8,14,20,24,
14,20,24,28,
20,24,28,33,
24,28,33,39
INTRA4X4_CHROMAU =
 9,13,18,21,
13,18,21,25,
18,21,25,30,
21,25,30,35
INTRA4X4_CHROMAV =
10,14,19,22,
14,19,22,26,
19,22,26,31,
22,26,31,36
INTER4X4_LUMA =
10,14,19,23,
14,19,23,27,
19,23,27,30,
23,27,30,34
INTER4X4_CHROMAU =
10,14,19,23,
14,19,23,27,
19,23,27,30,
23,27,30,34
INTER4X4_CHROMAV =
10,14,19,23,
14,19,23,27,
19,23,27,30,
23,27,30,34
INTRA8X8_LUMA =
 7,10,13,15,17,21,24,26,
10,12,15,17,21,24,26,28,
13,15,17,21,24,26,28,30,
15,17,21,24,26,28,30,32,
17,21,24,26,28,30,32,35,
21,24,26,28,30,32,35,38,
24,26,28,30,32,35,38,40,
26,28,30,32,35,38,40,43
INTER8X8_LUMA =
 9,12,14,16,18,20,22,24,
12,13,16,18,20,22,24,25,
14,16,18,20,22,24,25,26,
16,18,20,22,24,25,26,28,
18,20,22,24,25,26,28,30,
20,22,24,25,26,28,30,31,
22,24,25,26,28,30,31,32,
24,25,26,28,30,31,32,34
"""


def synth(w: int, h: int, pat: str, seed: int = 3):
    rng = np.random.default_rng(seed)
    cw, ch = w // 2, h // 2
    if pat == "smooth":
        xx, yy = np.meshgrid(np.linspace(0, 6.0, w), np.linspace(0, 4.0, h))
        y = (128 + 90 * np.sin(xx) * np.cos(yy * 0.7)).clip(0, 255).astype(np.uint8)
        cxx, cyy = np.meshgrid(np.linspace(0, 3.0, cw), np.linspace(0, 2.0, ch))
        u = (128 + 70 * np.sin(cxx + 1)).clip(0, 255).astype(np.uint8)
        v = (128 + 70 * np.cos(cyy)).clip(0, 255).astype(np.uint8)
    elif pat == "grad":
        y = (np.add.outer(np.linspace(20, 230, h), np.linspace(0, 20, w))
             ).clip(0, 255).astype(np.uint8)
        u = np.broadcast_to(np.linspace(60, 200, cw)[None, :], (ch, cw)).astype(np.uint8)
        v = np.broadcast_to(np.linspace(200, 60, ch)[:, None], (ch, cw)).astype(np.uint8)
    else:
        y = rng.integers(0, 256, (h, w), dtype=np.uint8).astype(np.uint8)
        u = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
        v = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
    return y.tobytes() + u.tobytes() + v.tobytes()


CASES = [
    # (w, h, pattern, qp, cqm("jvt"/"file"), cavlc, no8x8, nodb)
    (16,  16,  "grad",   30, "jvt",  0, 1, 1),
    (64,  64,  "smooth", 26, "jvt",  0, 0, 1),
    (64,  64,  "smooth", 26, "jvt",  1, 0, 1),
    (64,  64,  "noise",  20, "jvt",  0, 1, 0),
    (100, 76,  "smooth", 30, "jvt",  1, 0, 0),
    (320, 240, "smooth", 32, "jvt",  0, 0, 0),
    (64,  64,  "smooth", 26, "file", 0, 0, 1),
    (64,  64,  "smooth", 26, "file", 1, 0, 1),
    (64,  64,  "noise",  24, "file", 0, 1, 0),
    (100, 76,  "grad",   28, "file", 1, 0, 0),
    (160, 128, "smooth", 36, "file", 0, 0, 0),
    (34,  18,  "grad",   26, "file", 0, 0, 1),
    (96,  96,  "smooth", 12, "file", 0, 0, 0),
    (96,  96,  "smooth", 46, "jvt",  0, 0, 0),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    cqmf = OUT / ".tmp_cqm.cfg"
    cqmf.write_text(CQMFILE)
    n = 0
    for w, h, pat, qp, cqm, cavlc, no8, nodb in CASES:
        tmp.write_bytes(synth(w, h, pat))
        name = (f"p11_{pat}_{w}x{h}_q{qp}_{cqm}"
                f"{'_cavlc' if cavlc else ''}{'_no8' if no8 else ''}"
                f"{'_nodb' if nodb else ''}")
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--profile", "high", "--qp", str(qp), "--slices", "1",
               "--frames", "1", "--input-res", f"{w}x{h}", "--input-csp",
               "i420", "--fps", "25"]
        cmd += ["--cqm", "jvt"] if cqm == "jvt" else ["--cqmfile", str(cqmf)]
        if cavlc: cmd.append("--no-cabac")
        if no8: cmd.append("--no-8x8dct")
        if nodb: cmd.append("--no-deblock")
        cmd += ["-o", str(b264), str(tmp)]
        subprocess.run(cmd, check=True, capture_output=True)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt",
                        "yuv420p", str(OUT / (name + ".yuv"))], check=True)
        n += 1
    tmp.unlink(missing_ok=True)
    cqmf.unlink(missing_ok=True)
    print(f"generated {n} Phase 11 vectors under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
