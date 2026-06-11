#!/usr/bin/env python3
"""
Mutation fuzz for the H.264 decoder (ASan/UBSan build).

Seeds: every .264 in verification/vectors. Mutations: random byte
flips, truncations, byte substitutions, and chunk duplication. Pass
criteria per run: the decoder exits cleanly (0 = decoded, 2 = clean
reject) with no sanitizer report on stderr. Crashes and sanitizer
findings are saved under fuzz_failures/ for replay.
"""
from __future__ import annotations

import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VEC = ROOT / "verification" / "vectors"
FAIL = ROOT / "c_model" / "fuzz_failures"

N_PER_SEED = 40
TIMEOUT = 20


def mutate(data: bytes, rng: random.Random) -> bytes:
    b = bytearray(data)
    kind = rng.randrange(4)
    if kind == 0:                                  # bit flips
        for _ in range(rng.randint(1, 8)):
            i = rng.randrange(len(b))
            b[i] ^= 1 << rng.randrange(8)
    elif kind == 1:                                # truncate
        b = b[: rng.randrange(1, len(b))]
    elif kind == 2:                                # byte substitutions
        for _ in range(rng.randint(1, 16)):
            b[rng.randrange(len(b))] = rng.randrange(256)
    else:                                          # duplicate a chunk
        i = rng.randrange(len(b))
        n = min(rng.randint(1, 64), len(b) - i)
        b[i:i] = b[i: i + n]
    return bytes(b)


def main() -> int:
    binary = Path(sys.argv[1]).resolve()
    seeds = sorted(VEC.glob("*/*.264"))
    assert seeds, "no seed vectors"
    rng = random.Random(20260611)
    FAIL.mkdir(exist_ok=True)
    total = bad = 0
    tmp = FAIL / ".cur.264"
    for seed in seeds:
        data = seed.read_bytes()
        for k in range(N_PER_SEED):
            mut = mutate(data, rng)
            tmp.write_bytes(mut)
            total += 1
            try:
                r = subprocess.run(
                    [str(binary), str(tmp)],
                    capture_output=True, timeout=TIMEOUT, text=True)
                ok = r.returncode in (0, 2) and "ERROR: " not in r.stderr \
                    and "runtime error" not in r.stderr
            except subprocess.TimeoutExpired:
                ok = False
                r = None
            if not ok:
                bad += 1
                keep = FAIL / f"{seed.stem}_m{k}.264"
                keep.write_bytes(mut)
                why = "timeout" if r is None else \
                    f"rc={r.returncode} {r.stderr.strip().splitlines()[-1][:100] if r.stderr.strip() else ''}"
                print(f"[FAIL] {keep.name}: {why}")
    tmp.unlink(missing_ok=True)
    print(f"\nfuzz: {total} runs, {bad} failures "
          f"({'saved under ' + str(FAIL) if bad else 'all clean'})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
