#!/usr/bin/env python3
"""Validate the dimensions and alpha channel of generated distribution assets."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SIZES = {'iphone': {(1206, 2622), (1179, 2556)},
         'iphone-max': {(1320, 2868)},
         'iphone-air': {(1260, 2736)},
         'iphone-17e': {(1170, 2532)},
         'ipad': {(2064, 2752), (2048, 2732)},
         'duo': {(1398, 2034), (2034, 1398), (2007, 2853), (2853, 2007)}}

def properties(path):
    if not path.is_file():
        raise FileNotFoundError(f'Missing asset: {path}. Run screenshots.sh or make_icon.swift first.')
    output = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'hasAlpha', str(path)], text=True)
    values = dict(line.strip().split(': ', 1) for line in output.splitlines()[1:] if ': ' in line)
    return int(values['pixelWidth']), int(values['pixelHeight']), values['hasAlpha']

for size in [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]:
    path = ROOT / 'Release/Icons' / f'Folisona-{size}.png'
    assert properties(path) == (size, size, 'no'), path
print('13 icon sizes: OK')
for locale in ['es', 'en']:
    for family, sizes in SIZES.items():
        for screen in ['01-library', '02-chapters', '03-reader']:
            path = ROOT / 'Release/Screenshots' / locale / family / f'{screen}.jpg'
            width, height, alpha = properties(path)
            assert (width, height) in sizes and alpha == 'no', (path, width, height, alpha)
        print(f'{locale}/{family}: three screenshots, {width} x {height}, no alpha')

for locale in ['es', 'en']:
    for family, sizes in SIZES.items():
        for screen in ['01-library', '02-chapters', '03-reader']:
            path = ROOT / 'Release/StoreScreenshots' / locale / family / f'{screen}.jpg'
            width, height, alpha = properties(path)
            assert (width, height) in sizes and alpha == 'no', (path, width, height, alpha)
print('36 branded store screenshots: valid dimensions, no alpha')
