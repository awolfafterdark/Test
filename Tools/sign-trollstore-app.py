#!/usr/bin/env python3
"""Ad-hoc sign our own app with a deterministic, explicit application identity.
TrollStore applies its installation signing. This is not App Store signing.
"""
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

app = Path(sys.argv[1]).resolve()
report = Path(sys.argv[2]) if len(sys.argv) > 2 else None
info = plistlib.loads((app / 'Info.plist').read_bytes())
bundle_id = info['CFBundleIdentifier']
assert bundle_id.startswith('dev.pickerpatcher.')
team = 'PICKERPTCH'
expected = {
    'application-identifier': f'{team}.{bundle_id}',
    'com.apple.developer.team-identifier': team,
    'get-task-allow': False,
}
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'Entitlements.plist'
    path.write_bytes(plistlib.dumps(expected))
    subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none',
                    '--generate-entitlement-der', '--entitlements', str(path), str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    dump = subprocess.run(['codesign', '--display', '--entitlements', ':-', str(app)],
                          check=True, capture_output=True).stdout
    actual = plistlib.loads(dump)
    assert actual == expected, actual
    if report:
        report.write_text(json.dumps({'bundleIdentifier': bundle_id, 'entitlements': actual}, indent=2)+'\n')
print(f'Verified explicit ad-hoc identity for {bundle_id}')
