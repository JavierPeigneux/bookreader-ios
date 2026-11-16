#!/usr/bin/env python3
"""Capture real ES/EN UI on dedicated simulators; no scaling or fabricated playback."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
DEVICES = {'iphone': 'iPhone 18 Pro', 'iphone-max': 'iPhone 18 Pro Max', 'iphone-air': 'iPhone Air', 'iphone-17e': 'iPhone 17e', 'ipad': 'iPad Pro 13-inch (M5)', 'duo': 'iPhone Duo'}

def call(args, **kwargs):
    return subprocess.run(list(map(str, args)), cwd=ROOT, check=True, **kwargs)

def inventory(what):
    return json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', what, '-j']))[what]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--devices', nargs='+', choices=DEVICES, default=list(DEVICES))
    args = p.parse_args()
    runtimes = [r for r in inventory('runtimes') if r['isAvailable'] and r['version'] == '27.2']
    if not runtimes:
        p.error('Install the iOS 27.2 simulator runtime in Xcode first.')
    run_id = datetime.now().strftime('%Y%m%d-%H%M%S')
    working = ROOT / '.build' / 'store-screenshots' / run_id
    working.mkdir(parents=True)
    for family in args.devices:
        name = 'Folisona Store ' + family
        device_type = next(d['identifier'] for d in inventory('devicetypes') if d['name'] == DEVICES[family])
        runtime = next((r['identifier'] for r in runtimes
                        if any(d['identifier'] == device_type for d in r.get('supportedDeviceTypes', []))), None)
        if not runtime:
            p.error(f'No compatible iOS 27.2 runtime for {DEVICES[family]}; install it in Xcode.')
        existing = inventory('devices').get(runtime, [])
        device = next((d['udid'] for d in existing if d['name'] == name), None)
        if not device:
            device_type = next(d['identifier'] for d in inventory('devicetypes') if d['name'] == DEVICES[family])
            device = subprocess.check_output(['xcrun', 'simctl', 'create', name, device_type, runtime], text=True).strip()
        subprocess.run(['xcrun', 'simctl', 'boot', device], capture_output=True)
        call(['xcrun', 'simctl', 'bootstatus', device, '-b'], stdout=subprocess.DEVNULL)
        call(['xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41',
              '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3',
              '--batteryState', 'charged', '--batteryLevel', '100'])
        result = working / f'{family}.xcresult'
        log = working / f'{family}.log'
        env = dict(os.environ, TEST_RUNNER_FOLISONA_SCREENSHOTS='1')
        print(f'Capturing {family}: {log}', flush=True)
        try:
            with log.open('w') as f:
                call(['xcodebuild', '-project', 'FolisonaSimulator.xcodeproj', '-scheme', 'Folisona',
                      '-destination', f'platform=iOS Simulator,id={device}',
                      '-derivedDataPath', '.build/simulator272', '-clonedSourcePackagesDirPath', '.build/SourcePackages',
                      '-resultBundlePath', result, '-parallel-testing-enabled', 'NO',
                      '-only-testing:FolisonaUITests/ReaderUITests/testStoreSpanish',
                      '-only-testing:FolisonaUITests/ReaderUITests/testStoreEnglish',
                      'test', 'CODE_SIGNING_ALLOWED=NO'], env=env, stdout=f, stderr=subprocess.STDOUT)
            attachments = working / f'{family}-attachments'
            call(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', result, '--output-path', attachments], stdout=subprocess.DEVNULL)
            manifest = json.loads((attachments / 'manifest.json').read_text())
            exported = set()
            for test in manifest:
                for a in test.get('attachments', []):
                    match = re.match(r'Store-(es|en)-(\d\d-[a-z]+)', a.get('suggestedHumanReadableName', ''))
                    if not match or a.get('isAssociatedWithFailure'):
                        continue
                    language, screen = match.groups()
                    destination = ROOT / 'Release/Screenshots' / language / family
                    destination.mkdir(parents=True, exist_ok=True)
                    # JPEG has no alpha channel, as required by App Store Connect.
                    call(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '100',
                          attachments / a['exportedFileName'], '--out', destination / f'{screen}.jpg'], stdout=subprocess.DEVNULL)
                    exported.add((language, screen))
            if len(exported) != 6:
                raise RuntimeError(f'Expected six captures, got {len(exported)}. Inspect {log}')
            print(f'{family}: six screenshots exported.', flush=True)
        finally:
            subprocess.run(['xcrun', 'simctl', 'status_bar', device, 'clear'], capture_output=True)
            subprocess.run(['xcrun', 'simctl', 'shutdown', device], capture_output=True)
    print('Screenshots: Release/Screenshots. Review images and dimensions before uploading.')

if __name__ == '__main__':
    main()
