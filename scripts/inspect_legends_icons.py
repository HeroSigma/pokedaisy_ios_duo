#!/usr/bin/env python3
"""Find candidate icon pointers in the SHA-1 locked Legends Awakening ROM.

Unlike the first version, do NOT assume the source comment /*0xC4*/ is
the size of the final compiled SpeciesInfo (overworld fields extend it).
This is read-only diagnostic evidence; not proof of any individual member.
"""
import hashlib
import struct
import sys
from pathlib import Path

EXPECTED = "552ec33df5b6c31409fee1b8e5346e4a8de83ce9"
SPECIES_INFO = 0x0876A348
ICON_PALETTES = 0x0862C2F4
BASE = 0x08000000
SAMPLES = 128


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 scripts/inspect_legends_icons.py /path/to/pokeemerald.gba")
    path = Path(sys.argv[1])
    rom = path.read_bytes()
    digest = hashlib.sha1(rom).hexdigest()
    print(f"ROM: {path.name} ({len(rom):,} bytes)")
    print(f"SHA-1: {digest}")
    if digest != EXPECTED:
        sys.exit("STOP: ROM SHA-1 does not match the known Legends Awakening build.")

    start = SPECIES_INFO - BASE
    palette = ICON_PALETTES - BASE
    if start < 0 or palette < 0 or palette + 192 > len(rom):
        sys.exit("STOP: symbol addresses outside the ROM.")

    print(f"gSpeciesInfo: 0x{SPECIES_INFO:08X}")
    print(f"gMonIconPalettes: 0x{ICON_PALETTES:08X}")
    print("Scanning possible record strides (0xC4 to 0x400); "
          "source /*0xC4*/ comment is not necessarily final sizeof.")
    # With a correct stride, a real iconSprite pointer points at 1024+ bytes of
    # raw 4bpp tile graphics in nearly every populated species.
    # A wrong stride yields random pointer-shaped bytes only occasionally.
    candidates = []
    for stride in range(0xC4, 0x401, 4):
        for off in range(0, min(stride, 0x180) - 3, 4):
            valid = distinct = 0
            unique = set()
            first = []
            for species in range(1, SAMPLES + 1):
                record = start + species * stride + off
                if record + 4 > len(rom):
                    break
                ptr = u32(rom, record)
                pos = ptr - BASE
                if not (0 <= pos <= len(rom) - 1024):
                    continue
                valid += 1
                unique.add(ptr)
                if len(first) < 3:
                    first.append(f"{species}:0x{ptr:08X}")
            distinct = len(unique)
            if valid >= 90 and distinct >= 65:
                candidates.append((valid, distinct, stride, off, first))

    candidates.sort(reverse=True)
    if not candidates:
        print("No high-confidence pointer field detected. Do not enable icons yet.")
    for valid, distinct, stride, off, examples in candidates[:14]:
        print(f"stride=0x{stride:X}, member=+0x{off:X}, valid={valid}/{SAMPLES}, "
              f"distinct={distinct}, sample={', '.join(examples)}")
    print("IMPORTANT: Candidate entries may include description, pictures, "
          "iconSprite, or other pointer members.")
    print("Confirm with sizeof/offsetof from the exact game build before "
          "changing PokéDaisy's decoder.")
    print("No ROM or save data was modified.")


if __name__ == "__main__":
    main()
