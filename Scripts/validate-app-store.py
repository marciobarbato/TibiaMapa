#!/usr/bin/env python3
"""Validate local App Store candidate. Apple server validation remains separate."""
import pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == '2.3'
assert info['CFBundleIdentifier'] == 'barbato.TibiaMapa'
assert info['LSApplicationCategoryType'] == 'public.app-category.utilities'
entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
for key in ['app-sandbox', 'network.client', 'files.user-selected.read-write', 'files.bookmarks.app-scope']:
    assert entitlements.get('com.apple.security.' + key) is True, key
assert not any('temporary-exception' in key or key.endswith('network.server') for key in entitlements)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
archs = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/TibiaMapa')], text=True).split()
assert set(archs) == {'arm64', 'x86_64'}
privacy = plistlib.loads((app / 'Contents/Resources/PrivacyInfo.xcprivacy').read_bytes())
assert privacy['NSPrivacyTracking'] is False
assert privacy['NSPrivacyCollectedDataTypes'] == []
assert (app / 'Contents/Resources/MinimapSymbols.png').exists()
assert not list(app.rglob('*.xctest'))
if '--distribution' in sys.argv:
    assert not entitlements.get('com.apple.security.get-task-allow', False)
    signing = subprocess.check_output(['codesign', '-d', '--verbose=4', str(app)], stderr=subprocess.STDOUT, text=True)
    assert 'Authority=Apple Distribution:' in signing or 'Authority=3rd Party Mac Developer Application:' in signing
print('PASS: version, sandbox, folder bookmarks, privacy, universal binary, resources and code signature')
