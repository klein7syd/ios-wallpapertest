"""Local Windows companion; uses the installed iPASide engine and its active session.

No account password, private key, profile or signed IPA is uploaded. Ordinary
iPASide GUI sideloading provisions only one App ID. This probe provisions two,
uses zsign's repeated -m option, and checks both identities before installation.
The Windows/Apple/device stages are NOT verified by the cloud build.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

from verify_ipa import BASE_ID, GROUP_ID, ROOT, EXT, verify, require, profile_plist

REPAIR_VERSION = '0.0.2-build5-signing-r1'


def signing_assets(provision, app_id, serial, group, scratch, label):
    value = provision.ensure_signing_assets(
        app_id, serial, app_name='Native capability probe ' + label,
        app_groups=[group], on_step=lambda text: print(label + ': ' + text, flush=True))
    profile = scratch / (label + '.mobileprovision')
    profile.write_bytes(Path(value['profile_path']).read_bytes())
    parsed = profile_plist(profile.read_bytes())
    grant = parsed.get('Entitlements', {})
    require(group in grant.get('com.apple.security.application-groups', []),
            label + ': Apple profile did not grant the requested App Group. Stop before install.')
    require(grant.get('application-identifier', '').endswith('.' + app_id), label + ': App ID mismatch')
    require(serial.replace('-', '').lower() in {x.replace('-', '').lower() for x in parsed.get('ProvisionedDevices', [])},
            label + ': device absent from provisioning profile')
    return value, profile


def patch_unsigned(source, output, app_id, group):
    with zipfile.ZipFile(source) as z, zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as target:
        for info in z.infolist():
            data = z.read(info.filename)
            if info.filename in (ROOT + 'Info.plist', EXT + 'Info.plist'):
                plist = plistlib.loads(data)
                plist['CFBundleIdentifier'] = app_id + ('.widget' if info.filename.startswith(EXT) else '')
                plist['ProbeAppGroupIdentifier'] = group
                data = plistlib.dumps(plist, fmt=plistlib.FMT_BINARY)
            target.writestr(info, data)


def embed_profiles(source, output, main_profile, widget_profile):
    # Older zsign multi-profile versions embed the extension profile AFTER
    # generating CodeResources. Stage the exact bytes first so no resource is
    # added/changed after sealing, including when the signer writes them again.
    with zipfile.ZipFile(source) as z, zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as target:
        for info in z.infolist():
            target.writestr(info, z.read(info.filename))
        for prefix, profile in [(ROOT, main_profile), (EXT, widget_profile)]:
            require(prefix + 'embedded.mobileprovision' not in z.namelist(), 'Input already contains a profile')
            info = zipfile.ZipInfo(prefix + 'embedded.mobileprovision')
            info.external_attr = (0o100644 << 16)
            target.writestr(info, Path(profile).read_bytes())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa')
    parser.add_argument('--udid')
    parser.add_argument('--sign-only', action='store_true')
    args = parser.parse_args()
    source = Path(args.ipa).resolve()
    print('Signing repair: ' + REPAIR_VERSION, flush=True)
    verify(source, unsigned=True)
    from ipaside_engine import apps, developer, device, gsa, paths, provision, signing

    # Reuse the account that the user selected in iPASide; never prompt for credentials.
    gsa.load_session()
    serial = device.resolve_serial(args.udid)
    team = developer.list_teams()[0]['teamId']
    installed = apps.list_installed(serial)
    expected_old_id = BASE_ID + '.' + team
    candidates = [key for key in installed if key in (BASE_ID, expected_old_id)]
    require(len(candidates) == 1,
            'Cannot identify the existing build-1 app for this Apple account. Select its original account in iPASide; do not uninstall it.')
    app_id = candidates[0]
    group = GROUP_ID + '.' + team
    print('Existing app identity retained: ' + app_id, flush=True)
    print('Extension identity: ' + app_id + '.widget', flush=True)
    print('Shared group: ' + group, flush=True)
    out = source.parent / 'widget-probe-local-output'
    out.mkdir(exist_ok=True)
    report = {'repair_version':REPAIR_VERSION, 'source_sha256':verify(source, unsigned=True)['sha256'],
              'app_id':app_id, 'extension_id':app_id + '.widget', 'app_group':group,
              'cloud_compilation':'previously_verified', 'local_signing':'not_performed',
              'installation':'not_performed', 'device_widget_function':'not_verified',
              'data_retention_after_update':'not_verified'}
    report_path = out / 'local-result.json'
    def save():
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    save()
    # A short per-user temporary path also avoids zsign's Windows path-length limits.
    with tempfile.TemporaryDirectory(prefix='np-', dir=os.environ.get('TEMP')) as tmp:
        scratch = Path(tmp)
        main_bundle = None
        try:
            main_bundle, main_profile = signing_assets(provision, app_id, serial, group, scratch, 'app')
            # Provision writes a shared per-account cache. Preserve the main profile,
            # and restore it even if the extension's provisioning fails.
            ext_bundle, ext_profile = signing_assets(provision, app_id + '.widget', serial, group, scratch, 'widget')
            require(main_bundle['certificate_serial'] == ext_bundle['certificate_serial'], 'Certificates differ between targets')
            patched = scratch / 'input.ipa'
            patch_unsigned(source, patched, app_id, group)
            verify(patched, unsigned=True, expected_app_id=app_id, expected_group=group)
            prepared = scratch / 'profiles-staged.ipa'
            embed_profiles(patched, prepared, main_profile, ext_profile)
            signed = out / 'NativeInstallProbe-widgets-signed.ipa'
            if signed.exists():
                try:
                    verify(signed, expected_app_id=app_id, expected_group=group)
                    report['previous_signed_package'] = 'resource_and_code_hash_checks_passed'
                except Exception as old_error:
                    report['previous_signed_package'] = str(old_error)
                    print('Previous signed package check: ' + str(old_error), flush=True)
                save()
            # Repeated -m selects a distinct profile/entitlements for each bundle.
            # No -E flag: the Widget extension must survive signing.
            signer = signing.resolve_zsign()
            report['signer_sha256'] = hashlib.sha256(Path(signer).read_bytes()).hexdigest()
            version = subprocess.run([signer, '-v'], capture_output=True, text=True, encoding='utf-8', errors='replace')
            report['signer_version'] = (version.stdout + version.stderr).strip()
            print('Signer version: ' + report['signer_version'], flush=True)
            report['local_signing'] = 'attempting'
            save()
            command = [signer, '-k', main_bundle['p12_path'],
                       '-p', main_bundle['p12_password'], '-m', str(main_profile),
                       '-m', str(ext_profile), '-t', str(scratch), '-f', '-z', '6',
                       '-o', str(signed), str(prepared)]
            result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
            # Keep signing diagnostics locally; never print the command containing P12 options.
            (out / 'zsign.log').write_text(result.stdout + '\n' + result.stderr, encoding='utf-8')
            report['local_signing'] = 'tool_returned_success_integrity_check_pending' if result.returncode == 0 else 'tool_failed'
            save()
            require(result.returncode == 0, 'zsign failed; see widget-probe-local-output/zsign.log')
            structure = verify(signed, expected_app_id=app_id, expected_group=group)
            (out / 'signed-package-verification.json').write_text(json.dumps(structure, ensure_ascii=False, indent=2), encoding='utf-8')
            report.update(local_signing='tool_succeeded_profiles_entitlements_resources_and_code_hashes_checked', signed_sha256=structure['sha256'])
            save()
            print('SIGNING TOOL SUCCEEDED; BOTH IDENTITIES, APP GROUPS, RESOURCE SEALS AND CODE HASHES CHECKED.', flush=True)
            if not args.sign_only:
                print('Installing over the existing app; do not delete the app.', flush=True)
                report['installation'] = 'attempting'
                save()
                apps.install(str(signed), serial, progress=lambda value: print('Install: ' + str(value.get('Status', value.get('status', 'working'))), flush=True))
                current = apps.list_installed(serial).get(app_id)
                require(current is not None, 'Install returned but app not listed')
                expected_build = structure['bundles'][0]['build']
                require(str(current.get('build')) == str(expected_build), 'Installed build does not match this IPA')
                report.update(installation='device_install_service_returned_success_and_build_rechecked', installed_build=str(expected_build))
                save()
                print('INSTALL SERVICE SUCCEEDED. Open the app and run DEVICE-TEST.md; Widget functionality is still unverified.', flush=True)
            print('Use this companion for this probe. Ordinary iPASide auto-refresh is not verified with these two profiles.', flush=True)
            print('Local report: ' + str(report_path), flush=True)
        except Exception as error:
            if report['installation'] == 'attempting':
                report['installation'] = 'failed'
            report['failure'] = str(error)
            save()
            raise
        finally:
            if main_bundle is not None:
                # Return iPASide's last-used provisioning cache to the containing app.
                profile_path = scratch / 'app.mobileprovision'
                if profile_path.exists():
                    shutil.copyfile(profile_path, main_bundle['profile_path'])
                    Path(main_bundle['profile_path']).with_name('bundle.json').write_text(json.dumps(main_bundle, indent=2), encoding='utf-8')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('STOPPED: ' + str(error), flush=True)
        raise SystemExit(1)
