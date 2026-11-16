#!/usr/bin/env python3
"""Complete reviewed Folisona 1.0 (3) submission fields; never submit for review."""
import json
import time
from decimal import Decimal
from urllib.parse import urlencode
from store_upload import API, APP_ID, BUNDLE_ID, ROOT, credentials


def read_until(api, path, predicate):
    for _ in range(20):
        result = api.call('GET', path)
        if predicate(result):
            return result
        time.sleep(1)
    raise RuntimeError('Readback did not converge: ' + path)


def main():
    api = API(credentials())
    app = api.call('GET', f'apps/{APP_ID}')['data']
    assert app['attributes']['bundleId'] == BUNDLE_ID
    versions = api.listing(f'apps/{APP_ID}/appStoreVersions')
    version = next(v for v in versions if v['attributes']['versionString'] == '1.0' and v['attributes']['platform'] == 'IOS')
    assert version['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION'
    build = api.call('GET', f'appStoreVersions/{version["id"]}/build')['data']
    assert build['attributes']['version'] == '3' and build['attributes']['processingState'] == 'VALID'
    # Current audited build: system CryptoKit SHA256 identifiers and OS file
    # protection only; no proprietary or third-party encryption implementation.
    if build['attributes']['usesNonExemptEncryption'] is None:
        api.save('builds', {'usesNonExemptEncryption': False}, build['id'])
    else:
        assert build['attributes']['usesNonExemptEncryption'] is False
    read_until(api, f'builds/{build["id"]}', lambda r: r['data']['attributes']['usesNonExemptEncryption'] is False)
    print('Verified export compliance: build 3, usesNonExemptEncryption=false', flush=True)
    # A document reader displays user-imported content. No bundled commercial
    # catalogue, remote content service, DRM bypass, or external voice assets.
    # Third-party software is MIT with notices; system voices use Apple APIs.
    api.save('apps', {'contentRightsDeclaration': 'USES_THIRD_PARTY_CONTENT'}, APP_ID)
    read_until(api, f'apps/{APP_ID}', lambda r: r['data']['attributes']['contentRightsDeclaration'] == 'USES_THIRD_PARTY_CONTENT')
    print('Verified content rights declaration', flush=True)
    info = next(i for i in api.listing(f'apps/{APP_ID}/appInfos') if i['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION')
    api.save('appInfos', {}, info['id'], {'primaryCategory': ('appCategories', 'BOOKS')})
    read_until(api, f'appInfos/{info["id"]}?include=primaryCategory', lambda r: r['data']['relationships']['primaryCategory']['data'] == {'type': 'appCategories', 'id': 'BOOKS'})
    print('Verified primary category: BOOKS', flush=True)
    schedule = api.call('GET', f'apps/{APP_ID}/appPriceSchedule?include=baseTerritory')['data']
    territory = schedule['relationships']['baseTerritory']['data']['id']
    try:
        manual = api.call('GET', f'appPriceSchedules/{schedule["id"]}/manualPrices?include=appPricePoint,territory')
    except RuntimeError as error:
        if 'HTTP 404' not in str(error):
            raise
        manual = {'data': []}
    if not manual['data']:
        points = api.listing(f'apps/{APP_ID}/appPricePoints?' + urlencode({'filter[territory]': territory, 'limit': 200}))
        free = next(p for p in points if Decimal(p['attributes']['customerPrice']) == 0)
        new_id = '${free-price}'
        payload = {'data': {'type': 'appPriceSchedules', 'relationships': {
            'app': {'data': {'type': 'apps', 'id': APP_ID}},
            'baseTerritory': {'data': {'type': 'territories', 'id': territory}},
            'manualPrices': {'data': [{'type': 'appPrices', 'id': new_id}]}}},
            'included': [{'type': 'appPrices', 'id': new_id,
                'attributes': {'startDate': None, 'endDate': None},
                'relationships': {'appPricePoint': {'data': {'type': 'appPricePoints', 'id': free['id']}}}}]}
        api.call('POST', 'appPriceSchedules', payload)
    # Check all automatic and manual territories, including future periods.
    count = 0
    for kind in ('manualPrices', 'automaticPrices'):
        path = f'appPriceSchedules/{APP_ID}/{kind}?include=appPricePoint,territory&limit=200'
        while path:
            result = api.call('GET', path)
            point_map = {x['id']: x for x in result.get('included', []) if x['type'] == 'appPricePoints'}
            for price in result['data']:
                point = price['relationships']['appPricePoint']['data']['id']
                assert Decimal(point_map[point]['attributes']['customerPrice']) == 0, 'Nonzero price detected'
                count += 1
            path = result.get('links', {}).get('next')
    assert count > 0
    report = {'version': '1.0', 'build': '3', 'usesNonExemptEncryption': False,
              'contentRightsDeclaration': 'USES_THIRD_PARTY_CONTENT', 'primaryCategory': 'BOOKS',
              'customerPrice': '0', 'verifiedPriceEntries': count, 'submittedForReview': False}
    (ROOT / 'Release/submission-setup-result.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Verified FREE pricing:', count, 'territory prices. Not submitted for review.')


if __name__ == '__main__':
    main()
