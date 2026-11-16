#!/usr/bin/env python3
"""Capture devices, build/upload an iOS version, and upload its bilingual store listing."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
import plistlib
from release import ROOT

def run(*args):
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version', default=None, help='Store version; defaults to Release/version.json (currently 1.0)')
    p.add_argument('--archive', type=Path, help='Reuse an archive instead of generating a new build')
    p.add_argument('--skip-captures', action='store_true', help='Reuse reviewed local captures')
    p.add_argument('--metadata-only', action='store_true', help='Resume after an already successful binary upload')
    p.add_argument('--replace-screenshots', action='store_true', help='Replace differing screenshots in affected display slots')
    a = p.parse_args()
    version = a.version or json.loads((ROOT / 'Release/version.json').read_text())['version']
    # Fail before a costly build if metadata access is unavailable.
    run(sys.executable, 'scripts/store_upload.py', '--check')
    if a.archive:
        a.archive = a.archive.expanduser().resolve()
        props = plistlib.loads((a.archive / 'Info.plist').read_bytes())['ApplicationProperties']
        if props['CFBundleIdentifier'] != 'com.javierpeigneux.Folisona' or props['CFBundleShortVersionString'] != version:
            raise ValueError('Archive bundle ID or marketing version differs from the destination')
    if not a.skip_captures:
        run('./scripts/screenshots.sh')
        run('swift', 'scripts/store_artwork.swift')
    run(sys.executable, 'scripts/check_release_assets.py')
    if not a.metadata_only:
        if a.archive:
            run('./scripts/release.sh', 'upload', '--archive', a.archive)
        else:
            run('./scripts/release.sh', 'upload', '--version', version, '--rebuild')
    extra = ['--replace-screenshots'] if a.replace_screenshots else []
    run(sys.executable, 'scripts/store_upload.py', '--version', version, *extra)
    if (ROOT / 'Release/StoreHeaders/folisona-header.png').is_file():
        run(sys.executable, 'scripts/store_headers.py', '--version', version)
    print('Store content and processed build association verified. No review submission or public release was requested by this command.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as e:
        raise SystemExit(str(e))
