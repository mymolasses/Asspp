"""Check packaging mechanics with a synthetic app; never builds a real IPA."""
import os
import pathlib
import plistlib
import subprocess
import tempfile
import zipfile

script = pathlib.Path(__file__).resolve().parents[2] / 'Resources/Scripts/compile.release.mobile.ci.sh'
with tempfile.TemporaryDirectory(prefix='asspp-packaging-check-') as temporary:
    root = pathlib.Path(temporary)
    checkout = root / 'checkout with spaces'
    configuration = checkout / 'Configuration'
    configuration.mkdir(parents=True)
    config = configuration / 'Developer.xcconfig'
    original_config = '// existing developer config fixture\nDEVELOPMENT_TEAM = FIXTURE\n'
    config.write_text(original_config)
    feature = checkout / 'uncommitted-feature.swift'
    feature.write_text('// uncommitted feature fixture\n')
    tools = root / 'bin'
    tools.mkdir()
    xcode = tools / 'xcodebuild'
    xcode.write_text('''#!/usr/bin/env python3
import pathlib, plistlib, sys
arguments = sys.argv[1:]
derived = pathlib.Path(arguments[arguments.index('-derivedDataPath') + 1])
app = derived / 'Build/Products/Release-iphoneos/Asspp.app'
app.mkdir(parents=True)
(app / 'Asspp').write_bytes(b'packaging-fixture-only')
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'wiki.qaq.Asspp', 'CFBundleExecutable': 'Asspp'}))
''')
    xcode.chmod(0o755)
    (tools / 'xcbeautify').symlink_to('/bin/cat')
    git = tools / 'git'
    git.write_text('#!/bin/sh\necho "Unexpected Git mutation in packaging script" >&2\nexit 99\n')
    git.chmod(0o755)
    output = root / 'output with spaces' / 'fixture-only.ipa'
    output.parent.mkdir()
    with zipfile.ZipFile(output, 'w') as old:
        old.writestr('stale-entry', b'must not survive')
    env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], LOCAL_SAP_LIBRARY_DIR=str(root / 'fixture-libs'))
    subprocess.run(['zsh', str(script), str(checkout), str(output)], env=env, check=True, capture_output=True, text=True)
    assert config.read_text() == original_config, 'Developer config was overwritten'
    assert feature.read_text() == '// uncommitted feature fixture\n', 'Working files were removed'
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert 'stale-entry' not in archive.namelist(), 'Archive retained stale entries'
        info = plistlib.loads(archive.read('Payload/Asspp.app/Info.plist'))
        assert info['CFBundleIdentifier'] == 'wiki.qaq.Asspp'
        assert archive.read('Payload/Asspp.app/Asspp') == b'packaging-fixture-only'
    assert not list((checkout / 'build').glob('package.*')), 'Temporary package directory leaked'
    print('PASS: packaging preserves working files/config, replaces stale archives, and handles paths with spaces')
