import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.make_solar_android_template import make_template, ANDROID


class SolarManifestTests(unittest.TestCase):
    def test_immersive_source_preserves_godot_launcher_and_other_files(self):
        manifest = b'''<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application><activity android:name=".GodotApp"/><activity-alias android:name=".GodotAppLauncher"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity-alias></application></manifest>'''
        with tempfile.TemporaryDirectory() as temporary:
            source, output = Path(temporary)/'source.zip', Path(temporary)/'output.zip'
            with zipfile.ZipFile(source, 'w') as z:
                z.writestr('AndroidManifest.xml', manifest)
                z.writestr('build.gradle', b'unchanged build source')
            make_template(source, output)
            with zipfile.ZipFile(output) as z:
                self.assertEqual(z.read('build.gradle'), b'unchanged build source')
                root = ET.fromstring(z.read('AndroidManifest.xml'))
            feature = root.find('uses-feature')
            self.assertEqual(feature.get(ANDROID+'name'), 'android.hardware.vr.headtracking')
            self.assertEqual(feature.get(ANDROID+'required'), 'true')
            categories = {n.get(ANDROID+'name') for n in root.findall('.//category')}
            self.assertTrue({'android.intent.category.LAUNCHER', 'org.khronos.openxr.intent.category.IMMERSIVE_HMD', 'com.oculus.intent.category.VR'}.issubset(categories))
            self.assertEqual(root.find('application/activity').get(ANDROID+'name'), '.GodotApp')
