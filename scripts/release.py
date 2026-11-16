#!/usr/bin/env python3
"""Build and upload Folisona with Xcode's signing. No third-party dependencies."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / 'Release'
VERSION = RELEASE / 'version.json'
PROJECTS = [ROOT / f'{n}.xcodeproj/project.xcproj' for n in ('Folisona', 'FolisonaSimulator')]


def next_version(current):
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', current):
        raise ValueError('Version must have format major.minor or major.minor.patch')
    a, b, c = (list(map(int, current.split('.'))) + [0])[:3]
    return f'{a}.{b}.{c + 1}'


def run(args):
    print('+', ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)


def settings():
    p = RELEASE / 'local.json'
    return json.loads(p.read_text()) if p.exists() else {}


def auth_args(config):
    values = [os.environ.get(k) or config.get(k) for k in
              ('ASC_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID')]
    if any(values) and not all(values):
        raise ValueError('Set all three ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID, or use the Xcode account.')
    if all(values):
        if not Path(values[0]).expanduser().is_file():
            raise ValueError('ASC_KEY_PATH does not point to a file')
        return ['-authenticationKeyPath', str(Path(values[0]).expanduser()),
                '-authenticationKeyID', values[1], '-authenticationKeyIssuerID', values[2]]
    return []


def preflight(config):
    run(['xcodebuild', '-version'])
    for p in ['Folisona/Resources/kokoro-v1_0.safetensors', 'Folisona/Resources/voices.npz',
              'Folisona/Assets.xcassets/AppIcon.appiconset/AppIcon.png']:
        if not (ROOT / p).is_file():
            raise ValueError(f'Missing {p}; run scripts/prepare_resources.py or make_icon.swift first.')
    auth_args(config)
    print('Local resources OK. Apple Developer membership, distribution signing and the App Store Connect record are checked by Apple at archive/upload time.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['check', 'archive', 'export', 'upload'])
    parser.add_argument('--version', help='Explicit version greater than the recorded version; default increments patch')
    parser.add_argument('--rebuild', action='store_true', help='Keep marketing version and increment build number')
    parser.add_argument('--archive', type=Path, help='Export or upload an existing archive without creating another version')
    args = parser.parse_args()
    config = settings()
    if args.archive and (args.command not in ('export', 'upload') or args.version or args.rebuild):
        parser.error('--archive is only valid with export/upload, without --version')
    preflight(config)
    if args.command == 'check':
        print('Current release:', VERSION.read_text().strip())
        return
    team = os.environ.get('FOLISONA_TEAM_ID') or config.get('FOLISONA_TEAM_ID')
    # The existing Xcode project team is used when no override is supplied.
    authentication = auth_args(config)
    RELEASE.mkdir(exist_ok=True)
    with (RELEASE / '.release.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.archive:
            archive = args.archive.expanduser().resolve()
            if not (archive / 'Info.plist').is_file():
                raise ValueError('Not a valid xcarchive')
            with (archive / 'Info.plist').open('rb') as f:
                archive_info = plistlib.load(f)
            if archive_info.get('ApplicationProperties', {}).get('CFBundleIdentifier') != 'com.javierpeigneux.Folisona':
                raise ValueError('Archive does not belong to Folisona')
        else:
            state = json.loads(VERSION.read_text())
            version = args.version or (state['version'] if args.rebuild else next_version(state['version']))
            next_version(version)  # Validate before comparing or writing.
            new_tuple = (list(map(int, version.split('.'))) + [0])[:3]
            old_tuple = (list(map(int, state['version'].split('.'))) + [0])[:3]
            if new_tuple < old_tuple or (new_tuple == old_tuple and not args.rebuild):
                raise ValueError('Version must be greater than the recorded version')
            build = int(state['build']) + 1
            if not 1 <= build <= 9999:
                raise ValueError('Local build counter exhausted; update version scheme before continuing')
            archive = RELEASE / 'Archives' / f'Folisona-{version}-{build}.xcarchive'
            if archive.exists():
                raise ValueError(f'Archive already exists: {archive}')
            updates = []
            for project in PROJECTS:
                text = project.read_text()
                for key, value in [('MARKETING_VERSION', version), ('CURRENT_PROJECT_VERSION', str(build))]:
                    text, count = re.subn(r'("' + key + r'"\s*:\s*")[^"]+(\")', lambda m: m[1] + value + m[2], text)
                    if count != 1:
                        raise ValueError(f'Expected one {key} in {project}')
                updates.append((project, text))
            # Reserve before building: failures never silently reuse a release number.
            pending = VERSION.with_suffix('.tmp')
            pending.write_text(json.dumps({'version': version, 'build': build}, indent=2) + '\n')
            pending.replace(VERSION)
            for project, text in updates:
                project.write_text(text)
            run(['xcrun', 'swift', 'scripts/make_icon.swift'])
            cmd = ['xcodebuild', '-project', 'Folisona.xcodeproj', '-scheme', 'Folisona',
                   '-configuration', 'Release', '-destination', 'generic/platform=iOS',
                   '-archivePath', archive, '-derivedDataPath', '.build/release',
                   '-clonedSourcePackagesDirPath', '.build/SourcePackages',
                   '-allowProvisioningUpdates', *authentication, 'archive',
                   f'MARKETING_VERSION={version}', f'CURRENT_PROJECT_VERSION={build}']
            if team:
                cmd.append(f'DEVELOPMENT_TEAM={team}')
            run(cmd)
        if args.command == 'archive':
            print(f'Archive ready: {archive}')
            return
        options = {'method': 'app-store-connect', 'destination': 'upload' if args.command == 'upload' else 'export',
                   'signingStyle': 'automatic', 'uploadSymbols': True,
                   'manageAppVersionAndBuildNumber': args.command == 'upload'}
        if team:
            options['teamID'] = team
        export = RELEASE / 'Exports' / archive.stem
        export.mkdir(parents=True, exist_ok=True)
        options_path = export / 'ExportOptions.plist'
        with options_path.open('wb') as f:
            plistlib.dump(options, f)
        run(['xcodebuild', '-exportArchive', '-archivePath', archive,
             '-exportPath', export, '-exportOptionsPlist', options_path,
             '-allowProvisioningUpdates', *authentication])
        if args.command == 'export':
            print(f'App Store distribution export completed: {export}')
            return
        print('Upload command completed. Check processing in App Store Connect/TestFlight. This does not submit the app for review or release it publicly.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f'Release stopped: {error}')
