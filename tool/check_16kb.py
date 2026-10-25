#!/usr/bin/env python3
"""Checks an APK for Android 15+ 16 KB page-size compatibility.

For every native library (lib/<abi>/*.so) it reports:
  * ELF LOAD segment alignment (must be >= 16384 on 64-bit ABIs), and
  * zip alignment of uncompressed libraries (offset % 16384 == 0), which
    lets the system map them straight from the APK.

Usage: python3 -I tool/check_16kb.py build/app/outputs/flutter-apk/app-release.apk
Exit code 1 when any 64-bit library fails.
"""
import struct
import sys
import zipfile

PAGE = 16384


def load_alignments(data: bytes):
    if data[:4] != b"\x7fELF":
        return None
    is64 = data[4] == 2
    little = data[5] == 1
    e = "<" if little else ">"
    if is64:
        phoff, = struct.unpack_from(e + "Q", data, 0x20)
        phentsize, phnum = struct.unpack_from(e + "HH", data, 0x36)
    else:
        phoff, = struct.unpack_from(e + "I", data, 0x1C)
        phentsize, phnum = struct.unpack_from(e + "HH", data, 0x2A)
    aligns = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type, = struct.unpack_from(e + "I", data, off)
        if p_type != 1:  # PT_LOAD
            continue
        if is64:
            p_align, = struct.unpack_from(e + "Q", data, off + 0x30)
        else:
            p_align, = struct.unpack_from(e + "I", data, off + 0x1C)
        aligns.append(p_align)
    return aligns


def main(path: str) -> int:
    failed = 0
    with zipfile.ZipFile(path) as z:
        for info in sorted(z.infolist(), key=lambda i: i.filename):
            name = info.filename
            if not (name.startswith("lib/") and name.endswith(".so")):
                continue
            abi = name.split("/")[1]
            sixty_four = abi in ("arm64-v8a", "x86_64")
            aligns = load_alignments(z.read(name)) or []
            elf_ok = bool(aligns) and min(aligns) >= PAGE
            stored = info.compress_type == zipfile.ZIP_STORED
            # Local header: 30 bytes + name + extra precede the data.
            with open(path, "rb") as f:
                f.seek(info.header_offset)
                header = f.read(30)
                n, m = struct.unpack_from("<HH", header, 26)
                data_offset = info.header_offset + 30 + n + m
            zip_ok = (not stored) or data_offset % PAGE == 0
            ok = elf_ok and zip_ok
            if sixty_four and not ok:
                failed += 1
            status = "OK  " if ok else ("FAIL" if sixty_four else "warn")
            detail = f"align={min(aligns) if aligns else '?'}"
            if stored:
                detail += f" zip={'aligned' if zip_ok else 'unaligned'}"
            print(f"{status} {name} ({detail})")
    print(f"\n{failed} 64-bit librar{'y' if failed == 1 else 'ies'} not 16 KB compatible")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
