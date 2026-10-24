"""Reproduce the zsign multi-profile bug using synthetic identities only.

No generated identity/profile is Apple-issued or usable for iPhone installation.
Only the original unsigned device IPA and public signing binaries are inputs.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile

from verify_ipa import BASE_ID, GROUP_ID, verify
from sign_widget_probe import embed_profiles


def run(command):
    result = subprocess.run([str(x) for x in command], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout + '\n' + result.stderr)
    return result.stdout + result.stderr


def test(ipa, old_signer, fixed_signer, output):
    verify(ipa, unsigned=True)
    report = {'scope':'synthetic_identity_resource_integrity_only', 'iphone_installation':'not_tested', 'cases':{}}
    with tempfile.TemporaryDirectory(prefix='probe-seal-') as temp:
        root = Path(temp)
        key, cert, der, p12 = [root / x for x in ['key.pem','cert.pem','cert.der','identity.p12']]
        ca_key, ca_cert, csr = [root / x for x in ['ca-key.pem','ca-cert.pem','leaf.csr']]
        run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',ca_key,'-out',ca_cert,'-days','1',
             '-subj','/CN=Native Probe Synthetic CA/O=Fixture Only','-addext','basicConstraints=critical,CA:TRUE'])
        run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-keyout',key,'-out',csr,
             '-subj','/CN=Native Probe Fixture/OU=PROBETEST1/O=Fixture Only'])
        extensions = root / 'leaf.ext'
        extensions.write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=codeSigning\n')
        run(['openssl','x509','-req','-in',csr,'-CA',ca_cert,'-CAkey',ca_key,'-CAcreateserial','-days','1',
             '-extfile',extensions,'-out',cert])
        run(['openssl','x509','-in',cert,'-outform','DER','-out',der])
        run(['openssl','pkcs12','-export','-inkey',key,'-in',cert,'-certfile',ca_cert,'-out',p12,'-passout','pass:fixture'])
        profiles = []
        for suffix in ['', '.widget']:
            name = 'app' if not suffix else 'widget'
            entitlement = {'application-identifier':'PROBETEST1.' + BASE_ID + suffix,
                           'com.apple.developer.team-identifier':'PROBETEST1',
                           'com.apple.security.application-groups':[GROUP_ID],
                           'get-task-allow':True, 'keychain-access-groups':['PROBETEST1.*']}
            plist = root / (name + '.plist')
            plist.write_bytes(plistlib.dumps({'UUID':name, 'Name':'SYNTHETIC fixture only', 'Version':1,
                'TeamIdentifier':['PROBETEST1'], 'ApplicationIdentifierPrefix':['PROBETEST1'],
                'CreationDate':datetime.datetime(2026,10,24), 'ExpirationDate':datetime.datetime(2026,10,25),
                'DeveloperCertificates':[der.read_bytes()], 'ProvisionedDevices':['0'*40], 'Entitlements':entitlement}))
            profile = root / (name + '.mobileprovision')
            run(['openssl','cms','-sign','-nodetach','-binary','-in',plist,'-signer',cert,'-inkey',key,'-outform','DER','-out',profile])
            profiles.append(profile)
        staged = root / 'staged.ipa'
        embed_profiles(ipa, staged, *profiles)
        for name, signer, source, should_pass in [
            ('old_signer_without_staging', old_signer, ipa, False),
            ('old_signer_with_staging', old_signer, staged, True),
            ('fixed_signer_without_staging', fixed_signer, ipa, True),
        ]:
            signed = root / (name + '.ipa')
            log = run([signer,'-k',p12,'-p','fixture','-m',profiles[0],'-m',profiles[1],'-f','-o',signed,source])
            Path(output, name + '.log').write_text(log, encoding='utf-8')
            try:
                checked = verify(signed)
                passed, detail = True, 'resource seals and code-directory hashes passed'
            except Exception as error:
                passed, detail = False, str(error)
            report['cases'][name] = {'integrity_passed':passed, 'detail':detail}
            if passed != should_pass:
                Path(output, 'fixture-result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
                raise AssertionError(name + ': ' + detail)
            if should_pass:
                # A real file changed after signing must be caught before installation.
                import zipfile
                tampered = root / 'tampered.ipa'
                with zipfile.ZipFile(signed) as z, zipfile.ZipFile(tampered,'w') as target:
                    for item in z.infolist():
                        data = z.read(item.filename)
                        if item.filename.endswith('NativeProbeWidget.appex/embedded.mobileprovision'):
                            data += b'changed-after-signing'
                        target.writestr(item, data)
                try:
                    verify(tampered)
                    raise AssertionError('Tampered Widget profile was accepted')
                except ValueError as error:
                    assert 'Sealed resource modified' in str(error), str(error)
        report['tampered_profile_rejection'] = 'passed'
        for label, selected, mutate, expected_error in [
            ('code_page', 'Payload/NativeInstallProbe.app/NativeInstallProbe',
             lambda data:data[:28] + bytes([data[28] ^ 1]) + data[29:], 'Executable code page changed'),
            ('resource_slot', 'Payload/NativeInstallProbe.app/_CodeSignature/CodeResources',
             lambda data:data + b'\n', 'CodeDirectory special-slot mismatch: 3'),
        ]:
            tampered = root / (label + '.ipa')
            with zipfile.ZipFile(signed) as z, zipfile.ZipFile(tampered,'w') as target:
                for item in z.infolist():
                    data = z.read(item.filename)
                    target.writestr(item, mutate(data) if item.filename == selected else data)
            try:
                verify(tampered)
                raise AssertionError('Accepted modification: ' + label)
            except ValueError as error:
                assert expected_error in str(error), str(error)
            report['tampered_' + label + '_rejection'] = 'passed'
    Path(output, 'fixture-result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa')
    parser.add_argument('old_signer')
    parser.add_argument('fixed_signer')
    parser.add_argument('output')
    args = parser.parse_args()
    Path(args.output).mkdir(parents=True, exist_ok=True)
    test(args.ipa, args.old_signer, args.fixed_signer, args.output)
