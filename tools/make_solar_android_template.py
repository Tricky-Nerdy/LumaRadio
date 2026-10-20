"""Add immersive-HMD declarations to the official Gradle Android template."""
import argparse
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ANDROID = '{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android', ANDROID[1:-1])
ET.register_namespace('tools', 'http://schemas.android.com/tools')


def make_template(source: Path, output: Path):
    changed = 0
    with zipfile.ZipFile(source) as src, zipfile.ZipFile(output, 'w') as dst:
        for info in src.infolist():
            data = src.read(info.filename)
            if info.filename.endswith('AndroidManifest.xml'):
                root = ET.fromstring(data)
                app = root.find('application')
                if app is not None and any(n.get(ANDROID + 'name', '').endswith('GodotApp') for n in app.findall('activity')):
                    changed += 1
                    feature = next((n for n in root.findall('uses-feature') if n.get(ANDROID + 'name') == 'android.hardware.vr.headtracking'), None)
                    if feature is None:
                        feature = ET.SubElement(root, 'uses-feature')
                    feature.attrib.update({ANDROID + 'name': 'android.hardware.vr.headtracking', ANDROID + 'version': '1', ANDROID + 'required': 'true'})
                    launchers = [n for n in app.findall('.//intent-filter') if any(c.get(ANDROID + 'name') == 'android.intent.category.LAUNCHER' for c in n.findall('category'))]
                    if not launchers:
                        raise ValueError('Godot template has no launcher intent')
                    for launcher in launchers:
                        names = {n.get(ANDROID + 'name') for n in launcher.findall('category')}
                        for name in ('org.khronos.openxr.intent.category.IMMERSIVE_HMD', 'com.oculus.intent.category.VR'):
                            if name not in names:
                                ET.SubElement(launcher, 'category', {ANDROID + 'name': name})
                    data = ET.tostring(root, encoding='utf-8', xml_declaration=True)
            dst.writestr(info, data)
    if changed != 1:
        output.unlink(missing_ok=True)
        raise ValueError(f'Expected exactly one Godot app manifest, found {changed}')
    print('Prepared Gradle source with head-tracking feature and immersive launch categories')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    make_template(args.source, args.output)
