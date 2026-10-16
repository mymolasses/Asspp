import datetime
import pathlib
import plistlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
base = {'CFBundleIdentifier': 'com.example.fixture', 'CFBundleDisplayName': 'Fixture App',
        'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '42', 'MinimumOSVersion': '16.0'}
profile = {'Name': 'Fixture Profile', 'TeamName': 'Fixture Team', 'TeamIdentifier': ['TESTTEAM'],
           'ProvisionsAllDevices': True, 'ExpirationDate': datetime.datetime(2020, 1, 1),
           'Entitlements': {'application-identifier': 'TESTTEAM.com.example.fixture'}}

def write(name, info=base, extra=None, binary=False):
    with zipfile.ZipFile(root / name, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('Payload/Fixture.app/Info.plist', plistlib.dumps(info, fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML))
        for path, data in (extra or {}).items():
            archive.writestr(path, data)

write('valid.ipa', extra={'Payload/Fixture.app/embedded.mobileprovision': b'FAKE-CMS-PREFIX' + plistlib.dumps(profile) + b'FAKE-CMS-SUFFIX',
                         'Payload/Fixture.app/_CodeSignature/CodeResources': b'fixture-resources',
                         'Payload/Fixture.app/PlugIns/Widget.appex/Info.plist': plistlib.dumps(base)})
write('binary.ipa', binary=True)
write('ambiguous.ipa', extra={'Payload/Other.app/Info.plist': plistlib.dumps(base)})
write('invalid-id.ipa', {**base, 'CFBundleIdentifier': '../../escape'})
write('unsafe-version.ipa', {**base, 'CFBundleShortVersionString': '../../escape'})
write('oversize.ipa', {**base, 'oversize': 'x' * (2 * 1024 * 1024)})
nameless = dict(base)
nameless.pop('CFBundleDisplayName')
write('nameless.ipa', nameless)
write('oversize-profile.ipa', extra={'Payload/Fixture.app/embedded.mobileprovision': b'x' * (8 * 1024 * 1024 + 1)})
corrupt = bytearray((root / 'valid.ipa').read_bytes())
central_header = corrupt.index(b'PK\x01\x02')
corrupt[central_header + 16] ^= 1
(root / 'bad-crc.ipa').write_bytes(corrupt)
with zipfile.ZipFile(root / 'nested-only.ipa', 'w') as archive:
    archive.writestr('Payload/Container.app/PlugIns/Nested.app/Info.plist', plistlib.dumps(base))
(root / 'broken.ipa').write_bytes(b'not a ZIP archive')
(root / 'wrong.txt').write_bytes(b'not an IPA')
