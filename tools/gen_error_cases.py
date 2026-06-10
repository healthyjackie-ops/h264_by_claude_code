#!/usr/bin/env python3
"""
Error-case vectors — corrupted/out-of-scope streams the decoder must
REJECT (rc != 0). Exercised by `golden_compare --expect-fail` via
`make errtest`, which also leak-checks every rejection on macOS.

Lesson imported from jpeg_by_claude_code: build error-path coverage the
moment the happy path lands, with a generator that verifies each case
actually fails before keeping it.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VEC = ROOT / "verification" / "vectors"
OUT = VEC / "error_cases"
DECODER = ROOT / "c_model" / "build" / "h264_decode"

SRC = VEC / "phase05" / "p05_grad_32x32_q30.264"


def encode_yuv(tmp: Path, w: int, h: int) -> None:
    tmp.write_bytes(bytes([128]) * (w * h * 3 // 2))


def x264(out: Path, w: int, h: int, args: list[str]) -> None:
    tmp = OUT / ".tmp.yuv"
    encode_yuv(tmp, w, h)
    subprocess.run(["x264", "--qp", "30", "--frames", "1",
                    "--input-res", f"{w}x{h}", "--input-csp", "i420",
                    "--fps", "25"] + args + ["-o", str(out), str(tmp)],
                   check=True, capture_output=True)
    tmp.unlink()


def strip_sps(data: bytes) -> bytes:
    """Drop the SPS NAL: slice arrives with no active parameter sets."""
    out = bytearray()
    i = 0
    while i < len(data):
        j = data.find(b"\x00\x00\x01", i)
        if j < 0:
            break
        start = j - 1 if j > 0 and data[j - 1] == 0 else j
        k = data.find(b"\x00\x00\x01", j + 3)
        end = len(data) if k < 0 else (k - 1 if data[k - 1] == 0 else k)
        nal_type = data[j + 3] & 0x1F
        if nal_type != 7:
            out += data[start:end]
        i = j + 3
    return bytes(out)


def main() -> int:
    if not DECODER.exists():
        print(f"build {DECODER} first", file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    src = SRC.read_bytes()

    cases: list[tuple[str, bytes]] = [
        ("err_trunc_midslice.264", src[: int(len(src) * 0.6)]),
        ("err_no_sps.264", strip_sps(src)),
        ("err_garbage.264", b"\x00\x00\x01\x65" + bytes(range(256)) * 4),
        ("err_empty_annexb.264", b"\x00\x00\x00\x01"),
    ]

    # Out-of-scope tools that must be cleanly rejected (CABAC graduated to
    # a supported feature in Phase 8/9 — interlaced replaces it here):
    interlaced = OUT / "err_interlaced.264"
    x264(interlaced, 64, 64, ["--profile", "main", "--slices", "1",
                              "--interlaced"])
    multislice = OUT / "err_multislice.264"
    x264(multislice, 64, 64, ["--profile", "baseline", "--slices", "4"])

    for name, data in cases:
        (OUT / name).write_bytes(data)

    n = 0
    for f in sorted(OUT.glob("*.264")):
        r = subprocess.run([str(DECODER), str(f)], capture_output=True, text=True)
        if r.returncode == 0:
            print(f"[GEN-FAIL] {f.name}: decoder ACCEPTED — investigate",
                  file=sys.stderr)
            f.unlink()
            return 1
        print(f"[ok] {f.name}  (rejected, {r.stderr.strip()})")
        n += 1
    print(f"generated {n} error cases under {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
