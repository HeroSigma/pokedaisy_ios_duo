#!/usr/bin/env python3
"""Read-only diagnostics for the exact Legends Awakening November 23 ROM.

Find plausible iconSprite member offsets in gSpeciesInfo without assuming
the pokeemerald-expansion SpeciesInfo layout. Does not change ROM/save data.
Results are candidates, not proof of an offset.
"""
import hashlib
import struct
import sys
from collections import Counter
from pathlib import Path

EXPECTED = "552ec33df5b6c31409fee1b8e5346e4a8de83ce9"
SPECIES_INFO = 0x0876A348
ICON_PALETTES = 0x0862C2F4
STRIDE = 0xC4  # struct SpeciesInfo /*0xC4*/ in this game source.
BASE = 0x08000000


def u32(rom, pos):
    return struct.unpack_from("<I", rom, pos)[0]


def read_ptr(rom, addr, length=512):
    pos = addr - BASE
    return pos if BASE <= addr and 0 <= pos <= len(rom) - length else None


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 scripts/inspect_legends_icons.py /path/to/pokeemerald.gba")
    path = Path(sys.argv[1])
    rom = path.read_bytes()
    digest = hashlib.sha1(rom).hexdigest()
    print(f"ROM: {path.name} ({len(rom):,} bytes)")
    print(f"SHA-1: {digest}")
    if digest != EXPECTED:
        sys.exit("STOP: wrong ROM build; this diagnostic is SHA-1 locked.")

    base = read_ptr(rom, SPECIES_INFO, STRIDE * 200)
    palette = read_ptr(rom, ICON_PALETTES, 6 * 32)
    if base is None or palette is None:
        sys.exit("STOP: expected symbol addresses fall outside the ROM.")
    print(f"gSpeciesInfo: 0x{SPECIES_INFO:08X}; stride candidate: 0x{STRIDE:X}")
    print(f"gMonIconPalettes: 0x{ICON_PALETTES:08X}")
    scores = []
    # Check candidate pointer members at the same offset in 160 species records.
    # Front/back graphics and description pointers may also score, so these
    # rankings must be checked against a separately compiled layout.
    for off in range(0, STRIDE - 3, 4):
        good = 0
        raw_like = 0
        compressed = 0
        examples = []
        unique = set()
        for species in range(1, 161):
            ptr = u32(rom, base + species * STRIDE + off)
            target = read_ptr(rom, ptr)
            if target is None:
                continue
            good += 1
            unique.add(ptr)
            payload = rom[target:target + 512]
            entropy_proxy = len(set(payload))
            if payload[0] == 0x10:
                compressed += 1
            if entropy_proxy >= 28 and any(payload) and payload[0] != 0x10:
                raw_like += 1
            if len(examples) < 3:
                examples.append(f"species {species}=0x{ptr:08X}")
        if good >= 30:
            scores.append((raw_like, good, len(unique), -compressed, off, examples))
    for raw_like, good, unique, neg_compressed, off, examples in sorted(scores, reverse=True)[:12]:
        print(f"member +0x{off:02X}: valid={good}/160, raw-like={raw_like}, "
              f"distinct={unique}, compressed={-neg_compressed}; " + ", ".join(examples))
    print("\nThese are candidate pointer fields, not confirmed iconSprite offsets.")
    print("Compare against offsetof(struct SpeciesInfo, iconSprite) from the matching build.")
    print("No files were modified.")


if __name__ == "__main__":
    main()
