#!/usr/bin/env python3
"""Synchronize public URLs, copyright and private review contact; never submit."""
import json
from store_upload import API, APP_ID, ROOT, credentials

def main():
    api = API(credentials())
    metadata = json.loads((ROOT / 'Release/metadata.json').read_text())
    contact = json.loads((ROOT / 'Release/local.json').read_text())['reviewContact']
    versions = api.listing(f'apps/{APP_ID}/appStoreVersions')
    version = next(v for v in versions if v['attributes']['versionString'] == '1.0' and v['attributes']['platform'] == 'IOS')
    vid = version['id']
    api.save('appStoreVersions', {'copyright': metadata['copyright']}, vid)
    for loc in api.listing(f'appStoreVersions/{vid}/appStoreVersionLocalizations'):
        saved = api.save('appStoreVersionLocalizations', {'supportUrl': metadata['supportURL']}, loc['id'])
        assert saved['attributes']['supportUrl'] == metadata['supportURL']
        print('Support URL saved:', loc['attributes']['locale'])
    infos = api.listing(f'apps/{APP_ID}/appInfos')
    info = next(i for i in infos if i['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION')
    for loc in api.listing(f'appInfos/{info["id"]}/appInfoLocalizations'):
        saved = api.save('appInfoLocalizations', {'privacyPolicyUrl': metadata['privacyPolicyURL']}, loc['id'])
        assert saved['attributes']['privacyPolicyUrl'] == metadata['privacyPolicyURL']
        print('Privacy URL saved:', loc['attributes']['locale'])
    detail = api.call('GET', f'appStoreVersions/{vid}/appStoreReviewDetail').get('data')
    attrs = {**contact, 'demoAccountRequired': False, 'notes': (ROOT / 'Release/review-notes-en.txt').read_text()}
    api.save('appStoreReviewDetails', attrs, identifier=detail['id'] if detail else None,
             relationships=None if detail else {'appStoreVersion': ('appStoreVersions', vid)})
    result = api.call('GET', f'appStoreVersions/{vid}/appStoreReviewDetail')['data']['attributes']
    assert all(result[k] == v for k, v in attrs.items())
    assert api.call('GET', f'appStoreVersions/{vid}')['data']['attributes']['copyright'] == metadata['copyright']
    print('Copyright and review details verified. Content rights and privacy declaration are separate. Not submitted.')

if __name__ == '__main__':
    main()
