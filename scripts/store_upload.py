#!/usr/bin/env python3
"""Upload and read back ES/EN metadata and screenshots using Apple's Connect API."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]
APP_ID = '6835442830'
BUNDLE_ID = 'com.javierpeigneux.Folisona'
# One real device per App Store display slot. Air is captured for visual QA;
# it shares the largest slot with Pro Max, so uploading both would duplicate cards.
SLOTS = {'iphone': 'APP_IPHONE_61', 'iphone-max': 'APP_IPHONE_67',
         'iphone-17e': 'APP_IPHONE_58', 'ipad': 'APP_IPAD_PRO_3GEN_129', 'duo': 'APP_IPHONE_DUO'}
SCREENS = ['01-library', '02-chapters', '03-reader']


def credentials():
    p = ROOT / 'Release/local.json'
    config = json.loads(p.read_text()) if p.exists() else {}
    values = {k: os.environ.get(k) or config.get(k) for k in ('ASC_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID')}
    if not all(values.values()):
        raise ValueError('Missing ASC_KEY_PATH, ASC_KEY_ID or ASC_ISSUER_ID in Release/local.json or environment. Xcode login cannot authenticate the metadata API.')
    values['ASC_KEY_PATH'] = str(Path(values['ASC_KEY_PATH']).expanduser())
    if not Path(values['ASC_KEY_PATH']).is_file():
        raise ValueError('ASC_KEY_PATH does not point to a file')
    return values


class API:
    def __init__(self, config):
        self.config = config

    def call(self, method, path, payload=None):
        import jwt
        now = int(time.time())
        token = jwt.encode({'iss': self.config['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 600,
                            'aud': 'appstoreconnect-v1'}, Path(self.config['ASC_KEY_PATH']).read_text(),
                           algorithm='ES256', headers={'kid': self.config['ASC_KEY_ID'], 'typ': 'JWT'})
        url = path if path.startswith('https://api.appstoreconnect.apple.com/') else 'https://api.appstoreconnect.apple.com/v1/' + path
        if not url.startswith('https://api.appstoreconnect.apple.com/'):
            raise ValueError('Unexpected API host')
        request = Request(url, data=json.dumps(payload).encode() if payload is not None else None,
                          headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}, method=method)
        try:
            with urlopen(request, timeout=90) as response:
                content = response.read()
                return json.loads(content) if content else {}
        except HTTPError as e:
            details = json.loads(e.read()).get('errors', [])
            raise RuntimeError(f'Apple API HTTP {e.code}: ' + '; '.join(x.get('detail', x.get('title', '')) for x in details)) from None

    def listing(self, path):
        results = []
        while path:
            reply = self.call('GET', path)
            results.extend(reply['data'])
            path = reply.get('links', {}).get('next')
        return results

    def save(self, kind, attrs, identifier=None, relationships=None):
        data = {'type': kind, 'attributes': attrs}
        if identifier:
            data['id'] = identifier
        if relationships:
            data['relationships'] = {k: {'data': {'type': v[0], 'id': v[1]}} for k, v in relationships.items()}
        return self.call('PATCH' if identifier else 'POST', kind + ('/' + identifier if identifier else ''), {'data': data})['data']


def wait_asset(api, identifier):
    for _ in range(120):
        data = api.call('GET', 'appScreenshots/' + identifier)['data']
        state = data['attributes']['assetDeliveryState']['state']
        if state == 'COMPLETE':
            return data
        if state == 'FAILED':
            raise RuntimeError('Apple could not process screenshot ' + identifier)
        time.sleep(5)
    raise RuntimeError('Screenshot processing timeout: ' + identifier)


def upload_image(api, set_id, path, existing):
    content = path.read_bytes()
    checksum = hashlib.md5(content).hexdigest()
    matching = next((x for x in existing if x['attributes'].get('sourceFileChecksum') == checksum and x['attributes'].get('assetDeliveryState', {}).get('state') in ('COMPLETE', 'UPLOAD_COMPLETE')), None)
    if matching:
        return wait_asset(api, matching['id'])
    # Recover only our own incomplete reservations; leave unrelated assets intact.
    for item in existing:
        if item['attributes'].get('fileName') == path.name and item['attributes']['assetDeliveryState']['state'] != 'COMPLETE':
            api.call('DELETE', 'appScreenshots/' + item['id'])
    asset = api.save('appScreenshots', {'fileName': path.name, 'fileSize': len(content)},
                     relationships={'appScreenshotSet': ('appScreenshotSets', set_id)})
    for op in asset['attributes']['uploadOperations']:
        request = Request(op['url'], data=content[op['offset']:op['offset']+op['length']],
                          headers={x['name']: x['value'] for x in op['requestHeaders']}, method=op['method'])
        # Do not send API credentials to Apple's separate asset storage host.
        try:
            with urlopen(request, timeout=120) as response:
                response.read()
        except Exception:
            raise RuntimeError('Screenshot byte transfer failed; retry the command (upload URL omitted).') from None
    api.save('appScreenshots', {'uploaded': True, 'sourceFileChecksum': checksum}, asset['id'])
    return wait_asset(api, asset['id'])


def localized_copy(metadata, primary_locale):
    copies = dict(metadata['localizations'])
    # Preserve an existing en-GB primary locale without leaving its product page empty.
    if primary_locale == 'en-GB' and 'en-US' in copies:
        copies.setdefault('en-GB', copies['en-US'])
    return copies


def select_build(builds, expected_build=None):
    return next((b for b in builds if not b['attributes'].get('expired')
                 and (expected_build is None or b['attributes']['version'] == str(expected_build))), None)


def upload(api, version, replace=False, expected_build=None):
    for locale in ('es', 'en'):
        for family in SLOTS:
            for name in SCREENS:
                if not (ROOT / 'Release/StoreScreenshots' / locale / family / (name + '.jpg')).is_file():
                    raise ValueError(f'Missing screenshot {locale}/{family}/{name}; run publish.sh first')
    app = api.call('GET', 'apps/' + APP_ID)['data']
    if app['attributes']['bundleId'] != BUNDLE_ID:
        raise ValueError('App ID does not match the expected bundle identifier')
    versions = api.listing(f'apps/{APP_ID}/appStoreVersions?' + urlencode({'filter[platform]': 'IOS'}))
    current = next((v for v in versions if v['attributes']['versionString'] == version), None)
    if current is None:
        current = api.save('appStoreVersions', {'platform': 'IOS', 'versionString': version, 'releaseType': 'MANUAL'},
                           relationships={'app': ('apps', APP_ID)})
    if current['attributes']['appStoreState'] not in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'):
        raise ValueError('The requested version is not editable; no store content was changed')
    metadata = json.loads((ROOT / 'Release/metadata.json').read_text())
    infos = api.listing(f'apps/{APP_ID}/appInfos')
    editable = next((x for x in infos if x['attributes']['appStoreState'] in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED')), None)
    if editable is None:
        raise ValueError('No editable App Information record')
    info_locales = api.listing('appInfos/' + editable['id'] + '/appInfoLocalizations')
    locales = api.listing('appStoreVersions/' + current['id'] + '/appStoreVersionLocalizations')
    verified = []
    copies = localized_copy(metadata, app['attributes'].get('primaryLocale'))
    for locale, copy in copies.items():
        attrs = {k: copy[k] for k in ('description', 'keywords', 'promotionalText')}
        if metadata.get('supportURL'):
            attrs['supportUrl'] = metadata['supportURL']
        existing = next((x for x in locales if x['attributes']['locale'] == locale), None)
        loc = api.save('appStoreVersionLocalizations', attrs if existing else dict(attrs, locale=locale),
                       existing['id'] if existing else None,
                       None if existing else {'appStoreVersion': ('appStoreVersions', current['id'])})
        # Apple may create App Information localization when the version locale is added.
        info_locales = api.listing('appInfos/' + editable['id'] + '/appInfoLocalizations')
        info = next((x for x in info_locales if x['attributes']['locale'] == locale), None)
        info_attrs = {'name': metadata['name'], 'subtitle': copy['subtitle']}
        if metadata.get('privacyPolicyURL'):
            info_attrs['privacyPolicyUrl'] = metadata['privacyPolicyURL']
        saved_info = api.save('appInfoLocalizations', info_attrs if info else dict(info_attrs, locale=locale),
                             info['id'] if info else None, None if info else {'appInfo': ('appInfos', editable['id'])})
        for kind, identifier, expected in [('appStoreVersionLocalizations', loc['id'], attrs), ('appInfoLocalizations', saved_info['id'], info_attrs)]:
            actual = api.call('GET', kind + '/' + identifier)['data']['attributes']
            if any(actual.get(k) != v for k, v in expected.items()):
                raise RuntimeError('Metadata readback mismatch: ' + locale)
        sets = api.listing('appStoreVersionLocalizations/' + loc['id'] + '/appScreenshotSets')
        for family, display in SLOTS.items():
            group = next((x for x in sets if x['attributes']['screenshotDisplayType'] == display), None)
            if group is None:
                group = api.save('appScreenshotSets', {'screenshotDisplayType': display},
                                 relationships={'appStoreVersionLocalization': ('appStoreVersionLocalizations', loc['id'])})
            items = api.listing('appScreenshotSets/' + group['id'] + '/appScreenshots')
            paths = [ROOT / 'Release/StoreScreenshots' / locale[:2] / family / (s + '.jpg') for s in SCREENS]
            hashes = {hashlib.md5(p.read_bytes()).hexdigest() for p in paths}
            outdated = [x for x in items if x['attributes'].get('sourceFileChecksum') not in hashes]
            if outdated and not replace:
                raise ValueError('Existing different screenshots: use --replace-screenshots to replace this version’s affected display sets')
            if replace:
                for item in outdated:
                    api.call('DELETE', 'appScreenshots/' + item['id'])
                items = [x for x in items if x not in outdated]
            uploaded = [upload_image(api, group['id'], p, items) for p in paths]
            api.call('PATCH', 'appScreenshotSets/' + group['id'] + '/relationships/appScreenshots',
                     {'data': [{'type': 'appScreenshots', 'id': x['id']} for x in uploaded]})
            actual = api.listing('appScreenshotSets/' + group['id'] + '/appScreenshots')
            if [x['id'] for x in actual] != [x['id'] for x in uploaded]:
                raise RuntimeError('Screenshot order readback mismatch')
            verified.append({'locale': locale, 'family': family, 'ids': [x['id'] for x in actual]})
            print(f'Verified {locale}/{family}: three screenshots COMPLETE', flush=True)
    # Attach the latest processed build for exactly this marketing version.
    selected = None
    for attempt in range(90):
        builds = api.listing('builds?' + urlencode({'filter[app]': APP_ID,
            'filter[preReleaseVersion.version]': version, 'filter[processingState]': 'VALID',
            'sort': '-uploadedDate', 'limit': 10}))
        selected = select_build(builds, expected_build)
        if selected:
            break
        print('Waiting for Apple to process the uploaded build...', flush=True)
        time.sleep(10)
    if selected is None:
        raise RuntimeError('Metadata uploaded, but no valid build for this version yet. Retry --metadata-only after processing.')
    api.call('PATCH', 'appStoreVersions/' + current['id'] + '/relationships/build',
             {'data': {'type': 'builds', 'id': selected['id']}})
    attached = api.call('GET', 'appStoreVersions/' + current['id'] + '/build')['data']
    if attached['id'] != selected['id']:
        raise RuntimeError('Build association readback mismatch')
    report = {'appId': APP_ID, 'version': version, 'versionId': current['id'], 'verifiedScreenshots': verified, 'buildId': selected['id'], 'buildNumber': selected['attributes']['version']}
    (ROOT / 'Release/store-upload-result.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Metadata and screenshots verified. Not submitted for review. Pricing/privacy/review details must be completed separately.')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version', default='1.0')
    p.add_argument('--check', action='store_true')
    p.add_argument('--build-number', help='Exact build to associate; defaults to the matching local release counter')
    p.add_argument('--replace-screenshots', action='store_true')
    args = p.parse_args()
    api = API(credentials())
    if args.check:
        app = api.call('GET', 'apps/' + APP_ID)['data']
        if app['attributes']['bundleId'] != BUNDLE_ID:
            raise ValueError('Unexpected bundle ID')
        print('API access verified for Folisona ' + APP_ID)
    else:
        expected = args.build_number
        if expected is None:
            local = json.loads((ROOT / 'Release/version.json').read_text())
            if local['version'] != args.version:
                raise ValueError('Specify --build-number when targeting a version other than the local release')
            expected = str(local['build'])
        upload(api, args.version, args.replace_screenshots, expected)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError) as e:
        raise SystemExit(str(e))
