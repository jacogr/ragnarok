#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Export independent current-profile STF bundles and verify recorded external RawState observations.

All binary framing, authenticated execution and complete-map comparison run in the native
checker. This tool owns bounded metadata, exact profile/file identities and process orchestration.
It does not launch an external implementation or claim that mathematical test doubles are
external-client evidence.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import selectors
import signal
import stat
import subprocess
import sys
import time
import tomllib

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_FORMAT = 'ragnarok-current-stf-bundle-v1'
PROFILE_FORMAT = 'ragnarok-stf-observation-profile-v1'
FILE_BYTES = 16 * 1024 * 1024
TOTAL_BYTES = 64 * 1024 * 1024
OUTPUT_BYTES = 65536


class ConformanceError(ValueError):
    """A bounded metadata/profile/process refusal never grants a successful observation comparison."""


def unique_object(pairs):
    """Reject duplicate JSON members rather than choosing one apparent profile or filename."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise ConformanceError('Duplicate JSON member')
        result[key] = value
    return result


def reject_constant(value):
    """Nonfinite JSON values have no canonical metadata interpretation."""
    raise ConformanceError('Nonfinite JSON value')


def regular_bytes(path, limit):
    """Open a nonblocking regular file and retain at most the explicit cap, retiring its descriptor on every exit."""
    flags = os.O_RDONLY
    for name in ('O_NONBLOCK', 'O_CLOEXEC', 'O_NOFOLLOW'):
        flags |= getattr(os, name, 0)
    descriptor = os.open(path, flags)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ConformanceError('Expected a regular file')
        parts = []
        used = 0
        while True:
            chunk = os.read(descriptor, min(65536, limit - used + 1))
            if not chunk:
                break  # Only actual EOF authorizes the complete bounded metadata or artifact.
            used += len(chunk)
            if used > limit:
                raise ConformanceError('File byte limit exceeded')
            parts.append(chunk)
        return b''.join(parts)
    finally:
        os.close(descriptor)  # No failed file/profile can retain a live descriptor.


def metadata(path, limit):
    """Decode strict bounded UTF-8 JSON without executable configuration or duplicate-key fallback."""
    return json.loads(regular_bytes(path, limit).decode('utf-8'),
                      object_pairs_hook=unique_object, parse_constant=reject_constant)


def hex_word(value, length):
    """Recognize exactly one lowercase fixed-width hexadecimal metadata representation."""
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{'+str(length)+'}', value) is not None


def member(root, name):
    """Resolve only canonical relative members inside the supplied immutable bundle namespace."""
    if not isinstance(name, str) or not name or len(name) > 4096 or '\\' in name:
        raise ConformanceError('Invalid bundle member')
    path = PurePosixPath(name)
    if path.is_absolute() or str(path) != name or any(part in ('.', '..') for part in path.parts):
        raise ConformanceError('Noncanonical bundle member')
    selected = root.joinpath(*path.parts)
    if not selected.resolve().is_relative_to(root.resolve()):
        raise ConformanceError('Escaping bundle member')
    return selected


def pins():
    """Bind exported evidence to unchanged project pins and the actual locked native VRF dependency."""
    configured = metadata(ROOT/'spec/pins.json', 1024 * 1024)
    lock = tomllib.loads(regular_bytes(ROOT/'native/bandersnatch/Cargo.lock', 1024 * 1024).decode())
    vrf = next(package for package in lock['package'] if package['name'] == 'ark-vrf')
    gp = configured['graypaper']['commit']
    version = subprocess.check_output(
        ['git', '-C', str(ROOT/'vendor/graypaper'), 'show', gp+':VERSION'],
        text=True, timeout=10).strip()
    revision = subprocess.check_output(
        ['git', '-C', str(ROOT/'vendor/ark-vrf'), 'rev-parse', 'HEAD'],
        text=True, timeout=10).strip()
    return dict(graypaper_commit=gp, graypaper_version=version,
                vectors_commit=configured['vectors']['commit'],
                ark_vrf_version=vrf['version'], ark_vrf_commit=revision)


def export_bundle(destination, policy):
    """Materialize only independent authored inputs in a fresh directory; existing official fixtures and destinations remain unchanged."""
    sys.path.insert(0, str(ROOT/'tests'))
    from current_stf_trace_command_oracle import expected_observations, FIXTURE
    jobs, answers, evidence = expected_observations()
    policy_bytes = regular_bytes(policy, 65536)
    if not policy_bytes.startswith(b'ragnarok-current-download-policy-v1\n'):
        raise ConformanceError('Wrong current resource-policy format')
    identity = pins()
    if json.loads(FIXTURE.read_text())['graypaper_commit'] != identity['graypaper_commit']:
        raise ConformanceError('Reference GP pin mismatch')
    destination.mkdir(parents=True, exist_ok=False)
    files = {}
    def put(name, value):
        """Write one exact independently supplied member exclusively and bind its complete SHA-256."""
        path = member(destination, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as stream:
            stream.write(value)
        files[name] = hashlib.sha256(value).hexdigest()
    put('current-policy.txt', policy_bytes)
    cases = []
    for ordinal, (job, answer) in enumerate(zip(jobs[:40], answers[:40])):
        case_id = 'case-'+str(ordinal).zfill(4)
        chain = case_id+'/chain.json'
        genesis = case_id+'/genesis.bin'
        put(chain, job['config'].encode())
        put(genesis, job['genesis'])
        steps = []
        for index, wire in enumerate(job['steps']):
            name = case_id+'/step-'+str(index).zfill(4)+'.bin'
            put(name, wire)
            steps.append(name)  # Every published binary input remains exactly the independent reference's bytes.
        _, status, count, root = answer.split(' ', 3)
        if status != 'None':
            raise ConformanceError('An authored success bundle contains a refused input')
        cases.append(dict(id=case_id, chain=chain, genesis=genesis, traces=steps,
                          parameters=json.loads(job['config'])['protocol_parameters'],
                          checked=int(count), final_root=root))
    manifest = dict(format=BUNDLE_FORMAT, pins=identity, policy='current-policy.txt',
                    reference_sha256=hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),
                    transitions=evidence['transitions'], cases=cases, files=dict(sorted(files.items())))
    with (destination/'manifest.json').open('x') as stream:
        json.dump(manifest, stream, indent=2, sort_keys=True)
        stream.write('\n')
    return dict(status='exported', cases=len(cases), transitions=evidence['transitions'],
                manifest=str((destination/'manifest.json').resolve()), pins=identity)


def bundle_manifest(root):
    """Admit closed finite metadata before reading payloads or starting any native checker."""
    manifest = metadata(root/'manifest.json', 1024 * 1024)
    fields = {'format', 'pins', 'policy', 'reference_sha256', 'transitions', 'cases', 'files'}
    if not isinstance(manifest, dict) or set(manifest) != fields or manifest['format'] != BUNDLE_FORMAT:
        raise ConformanceError('Invalid bundle metadata')
    if manifest['pins'] != pins() or not hex_word(manifest['reference_sha256'], 64):
        raise ConformanceError('Bundle/project pin mismatch')
    cases = manifest['cases']
    if not isinstance(cases, list) or not 1 <= len(cases) <= 256:
        raise ConformanceError('Case count exceeds bounds')
    member(root, manifest['policy'])
    references = {manifest['policy']}
    names = set()
    total = 0
    for case in cases:
        if not isinstance(case, dict) or set(case) != {'id', 'chain', 'genesis', 'traces', 'parameters', 'checked', 'final_root'}:
            raise ConformanceError('Invalid case metadata')
        if not isinstance(case['id'], str) or re.fullmatch(r'case-[0-9]{4}', case['id']) is None or case['id'] in names:
            raise ConformanceError('Invalid or duplicate case identity')
        names.add(case['id'])
        steps = case['traces']
        if not isinstance(steps, list) or not 1 <= len(steps) <= 256 or type(case['checked']) is not int or case['checked'] != len(steps):
            raise ConformanceError('Invalid finite trace sequence')
        if not hex_word(case['parameters'], 244) or not hex_word(case['final_root'], 64):
            raise ConformanceError('Invalid full profile or final commitment')
        for name in [case['chain'], case['genesis'], *steps]:
            member(root, name)  # Validate untrusted shape before hashing or set insertion.
            references.add(name)
        total += len(steps)  # The whole bundle has an independent aggregate work ceiling.
    if total > 4096 or type(manifest['transitions']) is not int or total != manifest['transitions']:
        raise ConformanceError('Invalid aggregate transition count')
    declared = manifest['files']
    if not isinstance(declared, dict) or set(declared) != references or len(declared) > 2048:
        raise ConformanceError('Incomplete or excessive artifact identities')
    for name, digest in declared.items():
        member(root, name)
        if not hex_word(digest, 64):
            raise ConformanceError('Invalid artifact SHA-256')
    return manifest


def target_profile(path):
    """Read declarations only; a GP version label never substitutes for an exact commit or full parameter tuple."""
    profile = metadata(path, 65536)
    if not isinstance(profile, dict) or set(profile) != {'format', 'client', 'graypaper_commit', 'graypaper_version', 'parameter_profiles'} or profile['format'] != PROFILE_FORMAT:
        raise ConformanceError('Invalid target-profile metadata')
    client = profile['client']
    if not isinstance(client, dict) or set(client) != {'name', 'version', 'artifact_sha256'}:
        raise ConformanceError('Invalid observation-source declaration')
    for field in ('name', 'version'):
        if not isinstance(client[field], str) or not 1 <= len(client[field]) <= 256:
            raise ConformanceError('Invalid observation-source text')
    if client['artifact_sha256'] is not None and not hex_word(client['artifact_sha256'], 64):
        raise ConformanceError('Invalid observation-source artifact identity')
    if profile['graypaper_commit'] is not None and not hex_word(profile['graypaper_commit'], 40):
        raise ConformanceError('Invalid target GP commit')
    version = profile['graypaper_version']
    if version is not None and (not isinstance(version, str) or len(version) > 80):
        raise ConformanceError('Invalid target GP version')
    parameters = profile['parameter_profiles']
    if not isinstance(parameters, list) or len(parameters) > 32 or any(not hex_word(value, 244) for value in parameters) or len(set(parameters)) != len(parameters):
        raise ConformanceError('Invalid target parameter declarations')
    return profile


def profile_refusal(manifest, profile, cases):
    """Refuse unknown/different profiles before opening observation files or invoking a native checker."""
    required = manifest['pins']
    if profile['graypaper_version'] is not None and profile['graypaper_version'] != required['graypaper_version']:
        return 'profile-mismatch', 'Declared GP version differs'
    if profile['graypaper_commit'] is None:
        return 'profile-unverified', 'Exact target GP commit is not declared'
    if profile['graypaper_commit'] != required['graypaper_commit']:
        return 'profile-mismatch', 'Declared GP commit differs'
    if not profile['parameter_profiles']:
        return 'profile-unverified', 'Complete target parameter profiles are not declared'
    if any(case['parameters'] not in profile['parameter_profiles'] for case in cases):
        return 'profile-mismatch', 'A selected full parameter tuple differs'
    return None


def checker_process(arguments, timeout):
    """Own one POSIX checker process group, bound both output streams and retire it on timeout or excessive output."""
    if os.name != 'posix':
        raise ConformanceError('This checker supervisor requires a POSIX native host')
    process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    streams = {'stdout': bytearray(), 'stderr': bytearray()}
    selector = selectors.DefaultSelector()
    completed = False
    try:
        selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
        selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
        deadline = time.monotonic()+timeout
        while selector.get_map():
            remaining = deadline-time.monotonic()
            if remaining <= 0:
                raise ConformanceError('Native checker timed out')
            for key, _ in selector.select(min(remaining, 0.2)):
                data = os.read(key.fd, 8192)
                if not data:
                    selector.unregister(key.fileobj)
                    continue  # Actual pipe EOF retires that stream without inventing a successful output.
                output = streams[key.data]
                if len(data) > OUTPUT_BYTES-len(output):
                    raise ConformanceError('Native checker output limit exceeded')
                output.extend(data)
        code = process.wait(timeout=max(0.01, deadline-time.monotonic()))
        completed = True
        return dict(exit_code=code, **{key:bytes(value).decode('utf-8', 'replace') for key, value in streams.items()})
    finally:
        selector.close()
        if not completed or process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)  # Also retire descendants holding pipes after the immediate child exits.
            except ProcessLookupError:
                pass  # The complete process group already retired.
            process.wait()  # Timeout/output/error paths cannot leave the checker or its inherited group alive.
        process.stdout.close()
        process.stderr.close()


def verify_observations(bundle, observations, profile_path, checker, selected=None, timeout=60):
    """Check recorded external post-states through native golden-plus-observed whole-map validation, without launching or claiming an external engine."""
    manifest = bundle_manifest(bundle)
    profile = target_profile(profile_path)
    cases = manifest['cases']
    if selected:
        wanted = set(selected)
        if len(wanted) != len(selected) or not wanted <= {case['id'] for case in cases}:
            raise ConformanceError('Unknown or duplicate selected case')
        cases = [case for case in cases if case['id'] in wanted]
    refusal = profile_refusal(manifest, profile, cases)
    base = dict(mode='recorded-external-observations', external_execution=False,
                source_declaration=profile['client'], pins=manifest['pins'], cases=[])
    if refusal:
        return dict(base, status=refusal[0], reason=refusal[1]), 4
    used = 0
    for name, expected in manifest['files'].items():
        data = regular_bytes(member(bundle, name), FILE_BYTES)
        used += len(data)
        if used > TOTAL_BYTES or hashlib.sha256(data).hexdigest() != expected:
            raise ConformanceError('Artifact identity or aggregate byte limit failed')
    for case in cases:
        configuration = metadata(member(bundle, case['chain']), FILE_BYTES)
        if not isinstance(configuration, dict) or configuration.get('protocol_parameters') != case['parameters']:
            raise ConformanceError('Configured-chain full parameter tuple differs from metadata')
    executable = checker.resolve()
    executable_hash = hashlib.sha256(regular_bytes(executable, 128*1024*1024)).hexdigest()
    results = []
    for case in cases:
        arguments = [str(executable), 'check-traces', '--trace-policy', str(member(bundle, manifest['policy'])),
                     '--trace-genesis', str(member(bundle, case['genesis'])), *[word for trace_file in ([str(member(bundle, name)) for name in case['traces']]) for word in ('--trace-file', trace_file)],
                     '--with-state', '--chain', str(member(bundle, case['chain'])),
                     '--state-writes', '1000', '--state-write-bytes', '1000000',
                     '--trace-observations', str((observations/case['id']).resolve())]
        checked = checker_process(arguments, timeout)
        wanted = 'TRACE_CHECK_OK checked='+str(case['checked'])+' root='+case['final_root']
        passed = checked['exit_code'] == 0 and checked['stdout'].strip() == wanted and not checked['stderr'].strip()
        results.append(dict(id=case['id'], passed=passed, **checked))  # Stored evidence distinguishes native comparison from declared external provenance.
    return dict(base, status='observations-match' if all(row['passed'] for row in results) else 'observations-rejected',
                checker_sha256=executable_hash, cases=results), 0 if all(row['passed'] for row in results) else 2


def main(argv=None):
    """Expose exclusive independent export and profile-bound recorded-observation verification without shell commands or fixture rewriting."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    export = commands.add_parser('export')
    export.add_argument('--output', type=Path, required=True)
    export.add_argument('--policy', type=Path, required=True)
    verify = commands.add_parser('verify')
    verify.add_argument('--bundle', type=Path, required=True)
    verify.add_argument('--observations', type=Path, required=True)
    verify.add_argument('--profile', type=Path, required=True)
    verify.add_argument('--checker', type=Path, required=True)
    verify.add_argument('--case', action='append')
    verify.add_argument('--timeout', type=float, default=60)
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == 'export':
            result, code = export_bundle(arguments.output, arguments.policy), 0
        else:
            if not 0 < arguments.timeout <= 120:
                raise ConformanceError('Checker timeout must be within120 seconds')
            result, code = verify_observations(arguments.bundle, arguments.observations,
                arguments.profile, arguments.checker, arguments.case, arguments.timeout)
    except (OSError, ValueError, KeyError, AssertionError, RecursionError, subprocess.SubprocessError) as error:
        result, code = dict(status='invalid-input', reason=str(error)[:2048], external_execution=False), 2
    print(json.dumps(result, sort_keys=True))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
