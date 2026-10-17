#!/usr/bin/env python3
"""Portable preflight regression checks for the shared Mach-O injector."""
import pathlib
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def fixture(path, *, padding=4096, encrypted=False):
    header = struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 2, 2, 72 + 80 + 24, 0, 0)
    segment = struct.pack('<II16sQQQQIIII', 0x19, 152, b'__TEXT', 0, 8192, 0, 8192, 0, 0, 1, 0)
    section = struct.pack('<16s16sQQIIIIIIII', b'__text', b'__TEXT', 0, 32, padding, 0, 0, 0, 0, 0, 0, 0)
    encryption = struct.pack('<6I', 0x2c, 24, 0, 0, int(encrypted), 0)
    path.write_bytes((header + segment + section + encryption).ljust(padding, b'\0') + b'B' * 32)


def main():
    with tempfile.TemporaryDirectory() as scratch:
        scratch = pathlib.Path(scratch)
        exe = scratch / 'inject'
        subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-DPP_STANDALONE',
                        str(ROOT / 'Core/MachOInject.c'), '-o', str(exe)], check=True)
        target = scratch / 'target'
        path = '@executable_path/Frameworks/PickerPatcherEmbedded.framework/PickerPatcherEmbedded'
        fixture(target)
        original = target.read_bytes()
        subprocess.run([str(exe), str(target), path], check=True)
        patched = target.read_bytes()
        assert len(patched) == len(original)
        assert struct.unpack_from('<I', patched, 16)[0] == 3
        assert path.encode() in patched
        assert patched[4096:] == original[4096:]
        assert subprocess.run([str(exe), str(target), path], capture_output=True).returncode != 0
        fixture(target, padding=256)
        original = target.read_bytes()
        assert subprocess.run([str(exe), str(target), path], capture_output=True).returncode != 0
        assert target.read_bytes() == original
        fixture(target, encrypted=True)
        original = target.read_bytes()
        assert subprocess.run([str(exe), str(target), path], capture_output=True).returncode != 0
        assert target.read_bytes() == original
    print('Mach-O injector: insertion, duplicate, padding, and encryption checks passed')


if __name__ == '__main__':
    main()
