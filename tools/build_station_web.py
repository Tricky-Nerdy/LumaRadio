"""Bundle the same Forge studio assets for offline Android and the local receiver."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from station.programming import SYSTEM_PROMPT
from station.signals import MORSE


def render_bundle():
    station = ROOT / 'station'
    data = {'formats': json.loads((station / 'formats.json').read_text()),
            'solar': json.loads((station / 'solar.json').read_text()), 'morse': MORSE,
            'instructions': SYSTEM_PROMPT}
    encoded = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')
    html = (station / 'studio.html').read_text().replace('/*FORGE_CORE*/', (station / 'studio.js').read_text())
    html = html.replace('/*FORGE_DATA*/', encoded)
    return html


def bundle():
    html = render_bundle()
    targets = [ROOT / 'station/web/index.html', ROOT / 'forge-hub/android/assets/station.html']
    for target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(html)
    return html


if __name__ == '__main__':
    print(f'Bundled offline Forge station ({len(bundle())} characters)')
