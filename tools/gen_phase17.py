#!/usr/bin/env python3
"""
Phase 17 vectors — B frames (spatial direct, both entropies).

Translation motion through IDR+P+B GOPs: B_Skip/B_Direct_16x16 (spatial),
all B partition mode pairs, B_8x8 sub-types incl. direct, bi-prediction
averaging, POC display reordering, and the B deblock bS rules. Scope
pins: --b-pyramid none --no-weightb --weightp 0 --direct spatial.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "vectors" / "phase17"


def gen_seq(w, h, n, kind, seed=7):
    rng = np.random.default_rng(seed)
    cw, ch = w // 2, h // 2
    if kind == "noise":
        base_y = rng.integers(0, 256, (h, w), dtype=np.uint8).astype(np.uint8)
    else:
        base_y = (np.add.outer(np.linspace(20, 230, h), np.linspace(0, 30, w))
                  ).clip(0, 255).astype(np.uint8)
    base_u = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
    base_v = rng.integers(0, 256, (ch, cw), dtype=np.uint8).astype(np.uint8)
    frames = []
    for f in range(n):
        y = np.roll(base_y, (f * 3) % 7, axis=1)
        y = np.roll(y, (f * 2) % 5, axis=0)
        if kind == "scene" and f == n // 2:
            y = y.copy()
            y[h // 4: h // 2, w // 4: 3 * w // 4] = rng.integers(
                0, 256, (h // 4, w // 2), dtype=np.uint8)
        u = np.roll(base_u, f, axis=1)
        v = np.roll(base_v, f, axis=0)
        frames.append(y.tobytes() + u.tobytes() + v.tobytes())
    return b"".join(frames)


CASES = [
    # (w, h, nframes, kind, qp, nbf, cavlc, deblock-off)
    (64,  48,  4, "grad",  26, 1, 1, 1),
    (64,  48,  4, "grad",  26, 1, 0, 0),
    (64,  64,  6, "noise", 30, 2, 0, 0),
    (64,  64,  6, "noise", 30, 2, 1, 1),
    (100, 76,  6, "grad",  28, 2, 1, 0),
    (100, 76,  6, "grad",  28, 2, 0, 1),
    (160, 128, 7, "noise", 32, 2, 0, 0),
    (160, 128, 7, "scene", 30, 2, 1, 0),
    (320, 240, 6, "grad",  26, 3, 0, 0),
    (322, 242, 6, "grad",  32, 2, 0, 0),
    (34,  18,  5, "noise", 26, 1, 1, 0),
    (96,  96,  8, "noise", 20, 2, 1, 0),
    (96,  96,  8, "grad",  42, 2, 0, 0),
    (64,  48,  7, "scene", 24, 2, 0, 0),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp_src.yuv"
    n = 0
    for w, h, nf, kind, qp, nbf, cavlc, nodb in CASES:
        tmp.write_bytes(gen_seq(w, h, nf, kind))
        name = (f"p17_{kind}_{w}x{h}_n{nf}_q{qp}_b{nbf}"
                f"{'_cavlc' if cavlc else ''}{'_nodb' if nodb else ''}")
        b264 = OUT / (name + ".264")
        cmd = ["x264", "--profile", "main", "--qp", str(qp),
               "--frames", str(nf), "--ref", "1", "--slices", "1",
               "--bframes", str(nbf), "--b-pyramid", "none",
               "--no-weightb", "--weightp", "0", "--direct", "spatial",
               "--input-res", f"{w}x{h}", "--input-csp", "i420",
               "--fps", "25"]
        if cavlc:
            cmd.append("--no-cabac")
        if nodb:
            cmd.append("--no-deblock")
        cmd += ["-o", str(b264), str(tmp)]
        subprocess.run(cmd, check=True, capture_output=True)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(b264), "-f", "rawvideo", "-pix_fmt",
                        "yuv420p", str(OUT / (name + ".yuv"))], check=True)
        n += 1
    tmp.unlink(missing_ok=True)
    print(f"generated {n} Phase 17 vectors (+golden yuv) under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
