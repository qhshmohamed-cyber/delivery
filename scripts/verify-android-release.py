"""Fail the build before uploading an Android artifact with unsafe release flags."""
import sys
import xml.etree.ElementTree as ET
ns = '{http://schemas.android.com/apk/res/android}'
root = ET.parse(sys.argv[1]).getroot()
app = root.find('application')
assert app is not None, 'Missing application'
for key in ('allowBackup', 'usesCleartextTraffic'):
    assert app.get(ns + key) == 'false', f'{key} must be explicitly false'
assert app.get(ns + 'debuggable', 'false') == 'false', 'Debug APK cannot be distributed'
for key in ('fullBackupContent', 'dataExtractionRules'):
    assert app.get(ns + key), f'Missing {key}'
allowed = {'android.permission.INTERNET', 'com.yourstaff.delivery.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}
permissions = {p.get(ns + 'name') for p in root.findall('uses-permission')}
assert permissions <= allowed, 'New permission requires a privacy review'
assert root.get('package') == 'com.yourstaff.delivery', 'Unexpected app identity'
print('Release manifest verified: no debugging, backup or cleartext; permission allowlist passed.')
