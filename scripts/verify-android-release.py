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
allowed = {'android.permission.INTERNET', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION', 'android.permission.FOREGROUND_SERVICE', 'android.permission.FOREGROUND_SERVICE_LOCATION', 'android.permission.POST_NOTIFICATIONS', 'android.permission.WAKE_LOCK', 'com.yourstaff.delivery.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}
permissions = {p.get(ns + 'name') for p in root.findall('uses-permission')}
assert permissions <= allowed, 'New permission requires a privacy review'
assert root.get('package') == 'com.yourstaff.delivery', 'Unexpected app identity'
print('Release manifest verified: no debugging, backup or cleartext; permission allowlist passed.')

service=next((s for s in app.findall('service') if s.get(ns+'name','').endswith('.DriverLocationService')),None)
assert service is not None and service.get(ns+'exported')=='false'
assert service.get(ns+'foregroundServiceType')=='location'
assert service.get(ns+'stopWithTask')=='false'
assert 'android.permission.ACCESS_BACKGROUND_LOCATION' not in permissions
print('Driver foreground location service verified: private, typed, no boot receiver/background-location privilege.')
