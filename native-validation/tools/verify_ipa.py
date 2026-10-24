"""Structural checks only: these never claim iPhone installation or signature trust."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import zipfile

BASE_ID = 'org.todowallpaper.nativeinstallprobe'
GROUP_ID = 'group.' + BASE_ID
ROOT = 'Payload/NativeInstallProbe.app/'
EXT = ROOT + 'PlugIns/NativeProbeWidget.appex/'


def require(value, message):
    if not value:
        raise ValueError(message)


def profile_plist(data):
    start, end = data.find(b'<?xml'), data.find(b'</plist>')
    require(start >= 0 and end > start, 'Cannot read provisioning profile XML')
    return plistlib.loads(data[start:end + len(b'</plist>')])


def macho_info(data):
    require(len(data) >= 32 and data[:4] == b'\xcf\xfa\xed\xfe', 'Expected thin little-endian Mach-O 64')
    _, cpu, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from('<8I', data)
    require(cpu == 0x0100000C and filetype == 2, 'Expected ARM64 MH_EXECUTE')
    offset, platforms, signature = 32, [], None
    require(offset + sizeofcmds <= len(data), 'Truncated Mach-O commands')
    for _ in range(ncmds):
        command, size = struct.unpack_from('<II', data, offset)
        require(size >= 8 and offset + size <= 32 + sizeofcmds, 'Invalid load command')
        if command == 0x32:
            platforms.append(struct.unpack_from('<I', data, offset + 8)[0])
        if command == 0x1D:
            start, length = struct.unpack_from('<II', data, offset + 8)
            require(start + length <= len(data), 'Truncated signature')
            signature = data[start:start + length]
        offset += size
    require(platforms == [2], 'Not an iOS DEVICE executable')
    entitlements = None
    if signature:
        magic, length, count = struct.unpack_from('>III', signature)
        require(magic == 0xFADE0CC0 and length <= len(signature), 'Invalid signature superblob')
        for index in range(count):
            slot, position = struct.unpack_from('>II', signature, 12 + index * 8)
            if slot == 5:
                blob_magic, blob_size = struct.unpack_from('>II', signature, position)
                require(blob_magic == 0xFADE7171 and position + blob_size <= length, 'Invalid entitlement blob')
                entitlements = plistlib.loads(signature[position + 8:position + blob_size])
    return {'architecture':'arm64', 'platform':'iOS device', 'signature_present':signature is not None,
            'entitlements':entitlements}


def verify_code_hashes(data, info_data, resources_data):
    """Check code pages and special slots; this does not establish CMS trust."""
    position = 32
    signature = None
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, position)
        if command == 0x1D:
            start, length = struct.unpack_from('<II', data, position + 8)
            signature = data[start:start + length]
        position += size
    require(signature is not None, 'Missing code signature')
    magic, length, count = struct.unpack_from('>III', signature)
    require(magic == 0xFADE0CC0 and length <= len(signature), 'Invalid superblob')
    blobs = {}
    for index in range(count):
        slot, offset = struct.unpack_from('>II', signature, 12 + 8 * index)
        _, size = struct.unpack_from('>II', signature, offset)
        require(offset + size <= length, 'Truncated signature blob')
        blobs[slot] = signature[offset:offset + size]
    directories = [blob for slot, blob in blobs.items() if slot == 0 or 0x1000 <= slot <= 0x1005]
    require(directories, 'No CodeDirectory')
    for directory in directories:
        magic, size, version, _, hash_offset, _, special_count, page_count, code_limit = struct.unpack_from('>9I', directory)
        require(magic == 0xFADE0C02 and size == len(directory), 'Invalid CodeDirectory')
        hash_size, hash_type, _, page_exp = struct.unpack_from('>4B', directory, 36)
        algorithms = {1:'sha1', 2:'sha256', 3:'sha256', 4:'sha384'}
        require(hash_type in algorithms and page_exp <= 20, 'Unsupported code hash layout')
        if version >= 0x20300 and code_limit == 0xFFFFFFFF:
            code_limit = struct.unpack_from('>Q', directory, 56)[0]
        require(code_limit <= len(data), 'Code limit exceeds executable')
        def digest(value):
            return hashlib.new(algorithms[hash_type], value).digest()[:hash_size]
        for slot, value in [(1, info_data), (3, resources_data), (5, blobs.get(5)), (7, blobs.get(7))]:
            require(value is not None and special_count >= slot, 'Missing signed special slot ' + str(slot))
            offset = hash_offset - slot * hash_size
            require(offset >= 0 and directory[offset:offset + hash_size] == digest(value),
                    'CodeDirectory special-slot mismatch: ' + str(slot))
        page_size = (1 << page_exp) if page_exp else code_limit
        require(page_size > 0 and page_count == (code_limit + page_size - 1) // page_size, 'Invalid code page count')
        for index in range(page_count):
            chunk = data[index * page_size:min((index + 1) * page_size, code_limit)]
            offset = hash_offset + index * hash_size
            require(directory[offset:offset + hash_size] == digest(chunk), 'Executable code page changed')


def verify_resources(z, prefix, executable):
    """Validate zsign's flat resource seals, including files added after sealing."""
    resource_data = z.read(prefix + '_CodeSignature/CodeResources')
    seal = plistlib.loads(resource_data)
    files2 = seal.get('files2', {})
    rules = seal.get('rules2', {})
    require(isinstance(files2, dict) and isinstance(rules, dict), 'Invalid resource manifest')
    for section in ['files', 'files2']:
        for path, entry in seal.get(section, {}).items():
            full = prefix + path
            if full not in z.namelist():
                require(isinstance(entry, dict) and entry.get('optional'), 'Sealed resource missing: ' + full)
                continue
            data = z.read(full)
            hashes = {'hash':entry} if isinstance(entry, bytes) else entry
            require(isinstance(hashes, dict) and ('hash' in hashes or 'hash2' in hashes),
                    'Unsupported resource record: ' + full)
            for key, algorithm in [('hash','sha1'), ('hash2','sha256')]:
                if key in hashes:
                    require(hashlib.new(algorithm, data).digest() == hashes[key], 'Sealed resource modified: ' + full)
    for full in z.namelist():
        if not full.startswith(prefix) or full.endswith('/'):
            continue
        path = full[len(prefix):]
        if path == executable or path.startswith('_CodeSignature/') or path in files2:
            continue
        matches = []
        for pattern, rule in rules.items():
            if re.search(pattern, path):
                values = rule if isinstance(rule, dict) else {}
                matches.append((values.get('weight', 1), values))
        require(matches, 'No sealing rule for: ' + full)
        applicable = max(matches, key=lambda pair:pair[0])[1]
        require(applicable.get('omit') is True, 'Resource added after sealing: ' + full)
    return resource_data


def verify(path, *, unsigned=False, expected_app_id=BASE_ID, expected_group=GROUP_ID):
    results = []
    with zipfile.ZipFile(path) as z:
        require(z.testzip() is None, 'ZIP CRC failure')
        for name in z.namelist():
            require(not name.startswith('/') and '..' not in PurePosixPath(name).parts, 'Unsafe ZIP entry')
        require({n for n in z.namelist() if n.startswith(ROOT + 'PlugIns/') and n.endswith('.appex/Info.plist')}
                == {EXT + 'Info.plist'}, 'Expected exactly one embedded Widget extension')
        versions = []
        for prefix, bundle_id in [(ROOT, expected_app_id), (EXT, expected_app_id + '.widget')]:
            info = plistlib.loads(z.read(prefix + 'Info.plist'))
            require(info['CFBundleIdentifier'] == bundle_id, 'Unexpected Bundle ID: ' + info['CFBundleIdentifier'])
            require(info.get('ProbeAppGroupIdentifier') == expected_group, 'App Group Info.plist mismatch')
            if prefix == EXT:
                require(info.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension', 'Not a WidgetKit extension')
            versions.append((info['CFBundleShortVersionString'], info['CFBundleVersion']))
            executable_data = z.read(prefix + info['CFBundleExecutable'])
            binary = macho_info(executable_data)
            embedded = prefix + 'embedded.mobileprovision' in z.namelist()
            if unsigned:
                require(not binary['signature_present'] and not embedded, 'IPA is not unsigned')
                require(not any(n.startswith(prefix + '_CodeSignature/') for n in z.namelist()), 'Unexpected signature directory')
            else:
                require(binary['signature_present'] and embedded, 'Missing local signature/profile')
                grant = profile_plist(z.read(prefix + 'embedded.mobileprovision'))['Entitlements']
                signed = binary['entitlements'] or {}
                for source in [grant, signed]:
                    require(expected_group in source.get('com.apple.security.application-groups', []), 'App Group not granted/signed')
                    require(source.get('application-identifier', '').endswith('.' + bundle_id), 'Signing App ID mismatch')
                require(signed['application-identifier'] == grant['application-identifier'], 'Signature/profile identity mismatch')
                resources = verify_resources(z, prefix, info['CFBundleExecutable'])
                verify_code_hashes(executable_data, z.read(prefix + 'Info.plist'), resources)
                binary['resource_seal_verification'] = 'passed'
                binary['code_directory_hash_verification'] = 'passed'
            results.append({'bundle_id':bundle_id, 'version':versions[-1][0], 'build':versions[-1][1],
                            'app_group':info['ProbeAppGroupIdentifier'], 'embedded_profile':embedded, **binary})
        require(versions[0] == versions[1], 'App and extension versions differ')
    return {'sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest(), 'bundles':results,
            'structural_verification':'passed', 'cryptographic_signature_verification':'not_performed',
            'iphone_installation':'not_verified', 'device_capabilities':'not_verified'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa')
    parser.add_argument('--unsigned', action='store_true')
    parser.add_argument('--app-id', default=BASE_ID)
    parser.add_argument('--group', default=GROUP_ID)
    parser.add_argument('--report')
    args = parser.parse_args()
    report = verify(args.ipa, unsigned=args.unsigned, expected_app_id=args.app_id, expected_group=args.group)
    output = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        Path(args.report).write_text(output + '\n', encoding='utf-8')
    print(output)
