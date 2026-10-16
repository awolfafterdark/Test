#!/usr/bin/env python3
"""Set only the on-device patcher's visible display name for this build."""
import argparse
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('display_name')
args = parser.parse_args()
name = args.display_name.strip()
if not 1 <= len(name) <= 32 or any(ord(c) < 32 or ord(c) == 127 for c in name):
    parser.error('App display name must be 1–32 printable characters')
info = Path(__file__).resolve().parents[1] / 'PatcherApp' / 'Info.plist'
with info.open('rb') as stream:
    plist = plistlib.load(stream)
plist['CFBundleDisplayName'] = name
with info.open('wb') as stream:
    plistlib.dump(plist, stream)
print(f'On-device patcher display name: {name}')
