#!/usr/bin/env python3
"""Check the declared RF dimensions and optionally export the carrier CAD.

This validates numbers and geometry only, never physical RF performance.
"""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HARDWARE = ROOT / 'hardware/radio_dock_v0_1'


def validate(spec):
    if spec['format'] != 'AMID_RADIO_DOCK_TECHNICAL' or spec['version'] != 1:
        raise ValueError('Unknown hardware specification')
    frequency = spec['referenceFrequencyMHz']
    antenna = spec['antenna']
    if not 863 <= frequency <= 870:
        raise ValueError('This carrier specification is for EU868 only')
    quarter = antenna['speedOfLightMps'] / (frequency * 1e6) * 1000 / 4
    lower, upper = antenna['armTuningRangeMm']
    rod = antenna['initialArmLengthMm']
    if not lower <= rod <= upper or not .85 <= antenna['shorteningFactorEstimate'] <= 1:
        raise ValueError('Invalid experimental antenna dimensions')
    if antenna['coaxMaxLengthMm'] > 100 or antenna['feedImpedanceOhm'] != 50:
        raise ValueError('Unsupported feed specification')
    if spec['maxBlePacketBytes'] != 512 or spec['maxAppTextBytes'] != 200 or spec['maxHops'] != 3:
        raise ValueError('App/protocol bounds changed: review the radio implementation')
    return {
        'referenceFrequencyMHz': frequency,
        'wavelengthMm': quarter * 4,
        'quarterWaveMm': quarter,
        'estimatedShortenedArmMm': quarter * antenna['shorteningFactorEstimate'],
        'initialSpanMm': 2 * rod + antenna['feedGapMm'],
        'freeSpaceLossAt1KmDb': 20 * math.log10(4 * math.pi * 1000 / (quarter * 4 / 1000)),
        'physicalPerformanceVerified': False,
    }


def check_stl(path):
    # OpenSCAD's ASCII export makes all triangles auditable without extra libs.
    vertices = [tuple(round(float(x), 6) for x in line.split()[1:])
                for line in path.read_text().splitlines() if line.strip().startswith('vertex ')]
    if len(vertices) < 12 or len(vertices) % 3:
        raise ValueError('Invalid STL triangle stream')
    edges, volume = Counter(), 0.0
    for i in range(0, len(vertices), 3):
        a, b, c = vertices[i:i + 3]
        for p, q in [(a, b), (b, c), (c, a)]:
            edges[tuple(sorted((p, q)))] += 1
        volume += (a[0] * (b[1]*c[2] - b[2]*c[1]) -
                   a[1] * (b[0]*c[2] - b[2]*c[0]) +
                   a[2] * (b[0]*c[1] - b[1]*c[0])) / 6
    if any(count != 2 for count in edges.values()) or abs(volume) < 1:
        raise ValueError('Carrier is not a closed solid mesh')
    return {'triangles': len(vertices) // 3, 'absoluteVolumeMm3': abs(volume), 'closedMesh': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export-stl', type=Path)
    args = parser.parse_args()
    report = validate(json.loads((HARDWARE / 'radio_spec.json').read_text()))
    if args.export_stl:
        args.export_stl.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['openscad', '--export-format', 'asciistl', '-D', 'show_mockups=false',
                        '-o', str(args.export_stl.resolve()), str(HARDWARE / 'cad/phone_carrier.scad')], check=True)
        report['carrier'] = check_stl(args.export_stl)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
