"""Safety boundary: this SOS release must not gain silent telephony privileges."""
from pathlib import Path
import plistlib
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

class EmergencyPermissionsTests(unittest.TestCase):
    def test_android_keeps_system_confirmation_and_no_inbox_or_background_location_access(self):
        tree = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml')
        ns = '{http://schemas.android.com/apk/res/android}'
        permissions = {node.attrib[ns + 'name'] for node in tree.findall('uses-permission')}
        self.assertIn('android.permission.RECORD_AUDIO', permissions)
        for name in ['CALL_PHONE', 'SEND_SMS', 'READ_SMS', 'RECEIVE_SMS', 'READ_CONTACTS', 'ACCESS_BACKGROUND_LOCATION']:
            self.assertNotIn('android.permission.' + name, permissions)

    def test_ios_permission_purposes_exist_and_location_stays_foreground(self):
        info = plistlib.loads((ROOT / 'ios/Runner/Info.plist').read_bytes())
        for key in ['NSMicrophoneUsageDescription', 'NSSpeechRecognitionUsageDescription', 'NSLocationWhenInUseUsageDescription']:
            self.assertTrue(info[key].strip())
        self.assertNotIn('NSLocationAlwaysAndWhenInUseUsageDescription', info)
        self.assertNotIn('location', info.get('UIBackgroundModes', []))
        self.assertNotIn('audio', info.get('UIBackgroundModes', []))

if __name__ == '__main__':
    unittest.main()
