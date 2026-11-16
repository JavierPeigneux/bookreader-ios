#!/usr/bin/env python3
"""Upload reusable Folisona header through the App Asset Library API; never submit review."""
import argparse
import hashlib
import json
import struct
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from store_upload import API, APP_ID, BUNDLE_ID, ROOT, credentials

KIND = 'PRODUCT_PAGE_HEADER_ASSET'
READY = {'PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW', 'ACCEPTED', 'APPROVED'}

def png_size(content):
    if content[:8] != b'\x89PNG\r\n\x1a\n' or content[25] != 2:
        raise ValueError('Header must be an RGB PNG without alpha')
    return struct.unpack('>II', content[16:24])

def wait_image(api, identifier):
    for _ in range(120):
        image = api.call('GET', 'appAssetLibraryImages/' + identifier)['data']
        state = image['attributes']['state']
        if state in READY:
            return image
        if state not in ('AWAITING_UPLOAD', 'UPLOAD_COMPLETE'):
            raise RuntimeError('Header processing failed: ' + str(image['attributes'].get('stateDetails', state)))
        time.sleep(5)
    raise RuntimeError('Header processing timed out; rerun to resume')

def upload_headers(api, version):
    path = ROOT / 'Release/StoreHeaders/folisona-header.png'
    content = path.read_bytes()
    width, height = png_size(content)
    app = api.call('GET', 'apps/' + APP_ID)['data']
    if app['attributes']['bundleId'] != BUNDLE_ID:
        raise ValueError('Unexpected app bundle ID')
    refs = api.call('GET', 'appAssetLibraryRefData')['data'][0]['attributes']
    specs = [s for s in refs['imageSpecs'] if KIND in s['compatiblePlacementTypes']
             and s['dimensions']['minWidth'] <= width <= s['dimensions']['maxWidth']
             and s['dimensions']['minHeight'] <= height <= s['dimensions']['maxHeight']
             and '.png' in s['fileExtensions'] and len(content) <= s['maxFileSize']]
    if not specs:
        raise ValueError('Header does not match current Apple image specifications')
    placement = next(p for p in refs['placementTypes'] if p['placementTypeId'] == KIND)
    groups = [m['placementGroupId'] for m in placement['specMappings'] if any(s['specId'] in m['specs'] for s in specs)]
    if len(groups) != 1:
        raise ValueError('Expected exactly one compatible header placement group')
    group = groups[0]
    version_data = next(v for v in api.listing('apps/' + APP_ID + '/appStoreVersions')
                        if v['attributes']['versionString'] == version and v['attributes']['platform'] == 'IOS')
    if version_data['attributes']['appStoreState'] not in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'):
        raise ValueError('Version is not editable')
    locales = api.listing('appStoreVersions/' + version_data['id'] + '/appStoreVersionLocalizations')
    locales = [l for l in locales if l['attributes']['locale'] in ('es-ES', 'en-US', 'en-GB')]
    library = api.call('GET', 'apps/' + APP_ID + '/assetLibrary')['data']['id']
    reference = 'Folisona header ' + hashlib.sha256(content).hexdigest()[:20]
    images = api.listing('appAssetLibraries/' + library + '/images?' + urlencode({'filter[referenceName]': reference}))
    image = next((i for i in images if i['attributes']['referenceName'] == reference
                  and i['attributes']['state'] not in ('FAILED', 'REJECTED', 'ARCHIVED')), None)
    existing_placements = {}
    for loc in locales:
        existing = api.listing('appStoreVersionLocalizations/' + loc['id'] + '/placements?' + urlencode({'filter[placementType]': KIND, 'include': 'image'}))
        if any(p['relationships'].get('image', {}).get('data', {}).get('id') != (image or {}).get('id') for p in existing):
            raise ValueError('A different header already exists for ' + loc['attributes']['locale'] + '; no replacement performed')
        existing_placements[loc['id']] = existing
    if image is None:
        image = api.save('appAssetLibraryImages', {'fileName': path.name, 'fileSize': len(content),
            'category': 'CREATIVE_ASSETS', 'referenceName': reference},
            relationships={'assetLibrary': ('appAssetLibraries', library)})
    if image['attributes']['state'] == 'AWAITING_UPLOAD':
        for op in image['attributes']['uploadOperations']:
            request = Request(op['url'], data=content[op['offset']:op['offset'] + op['length']],
                              headers={h['name']: h['value'] for h in op['requestHeaders']}, method=op['method'])
            try:
                with urlopen(request, timeout=120) as response:
                    response.read()
            except Exception:
                raise RuntimeError('Header transfer failed; upload URL omitted. Rerun to resume.') from None
        api.save('appAssetLibraryImages', {'uploaded': True}, image['id'])
    image = wait_image(api, image['id'])
    if image['attributes']['specId'] not in {s['specId'] for s in specs}:
        raise RuntimeError('Apple matched an unexpected image specification')
    verified = []
    for loc in locales:
        existing = existing_placements[loc['id']]
        if not existing:
            api.save('appAssetLibraryPlacements', {'placementType': KIND, 'placementGroup': group},
                relationships={'image': ('appAssetLibraryImages', image['id']),
                               'appStoreVersionLocalization': ('appStoreVersionLocalizations', loc['id'])})
        readback = api.listing('appStoreVersionLocalizations/' + loc['id'] + '/placements?' + urlencode({'filter[placementType]': KIND, 'include': 'image'}))
        if len(readback) != 1 or readback[0]['relationships']['image']['data']['id'] != image['id']:
            raise RuntimeError('Header placement readback mismatch')
        state = readback[0]['attributes']['state']
        if state not in ('ACTIVE', 'PARENT_PREPARE_FOR_SUBMISSION'):
            raise RuntimeError('Unexpected placement state: ' + state)
        verified.append({'locale': loc['attributes']['locale'], 'placementId': readback[0]['id'], 'state': state})
        print('Verified header:', loc['attributes']['locale'], state, flush=True)
    report = {'appId': APP_ID, 'version': version, 'imageId': image['id'], 'sha256': hashlib.sha256(content).hexdigest(), 'placements': verified}
    (ROOT / 'Release/header-upload-result.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Headers uploaded and verified; not submitted for review.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', default='1.0')
    args = parser.parse_args()
    try:
        upload_headers(API(credentials()), args.version)
    except (ValueError, RuntimeError, OSError) as error:
        raise SystemExit(str(error))
