#!/usr/bin/env python3
"""Set the exact bundle filter for a local prototype build."""
import argparse
import plistlib
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("bundle_ids", help="Comma-separated exact bundle identifiers")
args = parser.parse_args()
ids = [item.strip() for item in args.bundle_ids.split(',')]
if not ids or any(not re.fullmatch(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+", item) for item in ids):
    parser.error("Expected comma-separated dotted bundle identifiers")
ids = list(dict.fromkeys(ids))
target = Path(__file__).with_name("PickerPatcher.plist")
with target.open("wb") as stream:
    plistlib.dump({"Filter": {"Bundles": ids}}, stream)
print(f"Configured exact injection filter: {', '.join(ids)}")
