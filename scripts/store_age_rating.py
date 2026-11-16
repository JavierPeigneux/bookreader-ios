#!/usr/bin/env python3
"""Apply the reviewed age questionnaire for Folisona's current offline reader."""
import json
from store_upload import API, APP_ID, BUNDLE_ID, ROOT, credentials


def main():
    api = API(credentials())
    app = api.call('GET', 'apps/' + APP_ID)['data']
    if app['attributes']['bundleId'] != BUNDLE_ID:
        raise ValueError('Unexpected app')
    info = next(x for x in api.listing('apps/' + APP_ID + '/appInfos')
                if x['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION')
    declaration = api.call('GET', 'appInfos/' + info['id'] + '/ageRatingDeclaration')['data']
    answers = json.loads((ROOT / 'Release/age-rating.json').read_text())['attributes']
    api.save('ageRatingDeclarations', answers, declaration['id'])
    actual = api.call('GET', 'appInfos/' + info['id'] + '/ageRatingDeclaration')['data']['attributes']
    if any(actual.get(k) != v for k, v in answers.items()):
        raise RuntimeError('Age rating readback mismatch')
    updated = api.call('GET', 'appInfos/' + info['id'])['data']['attributes']
    print('Age questionnaire saved and verified. Parental Controls: No (not implemented).')
    print(json.dumps({k:v for k,v in updated.items() if 'rating' in k.lower()}, indent=2))

if __name__ == '__main__':
    main()
