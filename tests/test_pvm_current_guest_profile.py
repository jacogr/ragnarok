# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Qualify Sieve/Pinky profiling with literal complete-state receipts and inert tool calls."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_current_guest_profile as profile
from pvm_performance_fixtures import invocation_observations, REVISION
from test_pvm_prepared_blocks import observed


def digest(data):
    """Give independent literal files their expected byte authority."""
    return hashlib.sha256(data).hexdigest()


def cohort(root):
    """Supply a complete passed canonical matrix with real selected input and image files."""
    value = json.loads(json.dumps(invocation_observations('all', 'x86_64')).replace(
        '/sealed/', str(root)+'/'))
    identity = value['identity']
    identity.update(clang='independent pinned Clang', build_environment={})
    files = identity['files']
    driver = root/'tests/performance/pvm_sieve.nim'
    files[str(driver)] = digest(b'independent original driver')
    artifact = root/'tests/fixtures/pvm-sieve/sieve.polkavm'
    artifact.parent.mkdir(parents=True)
    artifact.write_bytes(b'independent compact guest')
    files[str(artifact)] = digest(artifact.read_bytes())
    build, = [row for row in value['builds'] if row['family'] == 'guest']
    binary = Path(build['binary'])
    binary.write_bytes(b'independent sealed guest image')
    build['binary_sha256'] = files[str(binary)] = digest(binary.read_bytes())
    build['run']['command'] = [str(root/'compiler/nimony'), 'c', '--mm:arc', '--cc:clang',
        '-d:release', '--opt:speed', '--boundchecks:on', '--passC:-flto=thin',
        '--passL:-flto=thin', '--passL:-fuse-ld=lld', '-d:pvmX86Jit',
        '-d:pvmArm64JitOwnerReceipt', '--passC:-I'+str(root/'tests/performance'),
        '--passC:-I'+str(root/'native/pvm_jit'), '--nimcache:'+str(root/'cache'),
        '--out:'+str(binary), str(driver)]
    for guest, limit in (('sieve', 100000), ('sieve', 10000000), ('pinky', 1)):
        # Distinct literal inputs expose accidental cross-size fixture selection.
        folder = root/'inputs'/str(limit) if guest == 'sieve' else root/'inputs/pinky/1'
        folder.mkdir(parents=True)
        data, expected = folder/('input-'+str(limit)+'.bin'), folder/('expected-'+str(limit)+'.bin')
        for member in (data, expected):
            member.write_bytes((guest+':'+member.name).encode())
            files[str(member)] = digest(member.read_bytes())
        for row in value['runs']:
            if row['case_id'] != guest+'-'+str(limit) or row['role'] == 'reference':
                continue
            role = row['role']
            row['run'].update(command=[str(binary)], benchmark_environment=dict(
                RAGNAROK_PVM_BACKEND=role, RAGNAROK_PVM_PERFORMANCE='1',
                RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_PRICING='prepared',
                RAGNAROK_PVM_SIEVE_SAMPLES='13', RAGNAROK_PVM_SIEVE_CLOCK='1',
                RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_SIEVE_INPUT=str(data),
                RAGNAROK_PVM_SIEVE_EXPECTED=str(expected)))
            if guest == 'sieve':
                row['run']['benchmark_environment']['RAGNAROK_PVM_SIEVE_ARTIFACT'] = str(artifact)
            native = (dict(fragments=1, calls=12, operations=42, code_bytes=650, branches=12, headers=12)
                      if guest == 'sieve' else
                      dict(fragments=2, calls=24, operations=420, code_bytes=4096, branches=24, headers=0))
            if role == 'interpreted': native = dict.fromkeys(native, 0)
            row['parsed']['native'] = native
            row['parsed']['policy'].update(actual=role, **{key: native[key] for key in
                                                        ('fragments', 'calls', 'operations')})
    return value


def wire(limit, role, guest='sieve'):
    """Literal full-call grammar retains actual ownership and native activity without a real executable."""
    body = 'PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu\n'
    if guest != 'sieve':
        # The common scope receipt precedes the independent non-default family identity.
        body += 'GUEST,'+guest+'\n'
    body += observed(samples=13, clocked=True).replace(',1000,', ','+str(limit)+',')
    if role == 'jit':
        activity = ('1,12,42' if guest == 'sieve' else '2,24,420')
        occupancy = ('650,0,12,12' if guest == 'sieve' else '4096,0,24,0')
        body += ('PVM_POLICY,1,jit,1,1,1,jit,'+activity+'\n'
                 'ARM_OWNER,'+guest+','+activity+','+occupancy+'\n'
                 'PVM_RUNTIME_OWNER,1,guest-process,application-process,prestarted,1\n'
                 'PVM_RUNTIME_CLOSE,1,guest-process,3,7\n')
    else:
        body += ('PVM_POLICY,1,interpreted,1,1,0,interpreted,0,0,0\n'
                 'ARM_OWNER,'+guest+',0,0,0,0,0,0,0\n'
                 'PVM_RUNTIME_NONE,1,guest-process,interpreted-policy,1\n')
    return body+('PVM_NATIVE_COMPILATION,1,guest-process,0,0\n'
                 'PVM_OWNER_WINDOW,1,guest-process,1000000000,2000000000,includes-driver-oracles\n')


def counters(cost):
    """A complete independently written scope has distinct cold/reused simulated instruction totals."""
    return ('# callgrind format\npositions: line\nevents: Ir Bc Bcm Bi Bim\n'
            f'summary: {cost} 10 1 2 0\nfn=runPreparedKernel_literal\n1 {cost} 10 1 2 0\n'
            f'totals: {cost} 10 1 2 0\n')


class CurrentGuestProfile(unittest.TestCase):
    """Refuse wrong authority and incomplete observations before they become successful attribution."""
    def setUp(self):
        """Own a fresh inert image, canonical cohort and independent input files for each case."""
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.value = cohort(self.root)
        self.host = deepcopy(self.value['identity']['host'])
        self.path = self.root/'cohort.json'
        self.folder = self.root/'profile'
        self.mutation = None
        self.output_change = lambda text: text

    def run_profile(self):
        """Keep existing scope-calibration/source-binding helpers inert while exercising real guest parsing."""
        self.path.write_text(json.dumps(self.value))
        def command(arguments, name, **options):
            """A worst-case unfair scheduler leaves the compiler idle; fair collection retains native work."""
            if '--tool=callgrind' in arguments:
                role = options['environment']['RAGNAROK_PVM_BACKEND']
                guest = options['environment']['RAGNAROK_PVM_GUEST']
                limit = int(name.split('-')[1])
                target = Path(next(arg.split('=', 1)[1] for arg in arguments
                                   if str(arg).startswith('--callgrind-out-file=')))
                # Real collection still checks every part and the empty final dump.
                for index in range(1, 14):
                    target.with_name(target.name+'.'+str(index)).write_text(counters(99+index))
                target.write_text(counters(0).replace('10 1 2 0', '0 0 0 0'))
                output = wire(limit, role, guest)
                if role == 'jit' and '--fair-sched=yes' not in arguments:
                    output = output.replace('jit,1,1,1,jit,1,12,42', 'jit,1,1,1,interpreted,0,0,0')
                    output = output.replace('sieve,1,12,42,650,0,12,12', 'sieve,0,0,0,0,0,0,0')
                if self.mutation is not None: self.mutation()
                output = self.output_change(output)
            else:
                # Ordinary metadata/annotation calls cannot execute the inert sealed image.
                output = 'valgrind-3.22.0\n' if name == 'version' else (
                    '0000 T runPreparedKernel_literal\n' if name == 'guest-symbols' else '')
            return dict(command=list(map(str, arguments)), exit_code=0, output=output, log=name+'.log')
        with patch.dict(profile.os.environ, GITHUB_ACTIONS='true'), \
                patch.object(profile, 'host_identity', return_value=self.host), \
                patch.object(profile, 'canonical_source_identity', return_value={'revision': REVISION}), \
                patch.object(profile, 'canonical_tooling_seals', return_value={}), \
                patch.object(profile, 'calibrate_scope'), \
                patch.object(profile.NativeChecks, 'command', side_effect=command):
            return profile.profile_current_guest(self.path, REVISION, [100000, 10000000], self.folder)

    def test_original_images_keep_complete_calls_and_discard_clocks(self):
        """Keep original call identities and cold/reused simulated counters without timing samples."""
        report = self.run_profile()
        self.assertEqual(report['status'], 'passed')
        self.assertEqual([(row['case'], row['limit'], row['role']) for row in report['profiles']],
                         [('sieve', 100000, 'interpreted'), ('sieve', 100000, 'jit'),
                          ('sieve', 10000000, 'jit'), ('pinky', 1, 'interpreted'), ('pinky', 1, 'jit')])
        for row in report['profiles']:
            self.assertEqual((row['checked_calls'], row['cold']['Ir'], row['reused']['Ir']), (13, 100, 112))
            self.assertEqual(len(row['profile_hashes']), 14) # Thirteen returns and the empty final dump.
            self.assertNotIn('invocation', row)

    def test_pinky_requires_its_family_all_calls_and_native_working_set(self):
        """Neither a Sieve receipt, missing frame call nor changed native image can pass as Pinky."""
        diagnostics = dict(family='unknown execution output',
            call='foreign or out-of-order execution sample',
            native='native execution or code working set')
        for mutation in ('family', 'call', 'native'):
            def alter(text):
                """Damage only Pinky after every preceding Sieve profile has passed its controls."""
                if '\nGUEST,pinky\n' not in text: return text
                if mutation == 'family': return text.replace('GUEST,pinky', 'GUEST,sieve')
                if mutation == 'native':
                    return text.replace('pinky,2,24,420,4096', 'pinky,2,24,420,4097')
                return '\n'.join(line for line in text.splitlines()
                    if not line.startswith('SIEVE,ragnarok_prepared,1,7,'))+'\n'
            with self.subTest(mutation=mutation), self.assertRaisesRegex(ValueError, diagnostics[mutation]):
                self.output_change = alter
                self.run_profile()
            self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'failed')

    def test_pinky_snapshot_authority_cannot_be_replaced_by_an_extra_artifact(self):
        """Pinky must retain its original self-contained snapshot recipe and both sealed files."""
        for mutation in ('snapshot', 'expected', 'artifact', 'policy'):
            value = deepcopy(self.value)
            row = next(r for r in value['runs'] if (r['case_id'], r['role'], r['order']) ==
                       ('pinky-1', 'jit', 0))
            env = row['run']['benchmark_environment']
            if mutation in ('snapshot', 'expected'):
                key = 'RAGNAROK_PVM_SIEVE_'+('INPUT' if mutation == 'snapshot' else 'EXPECTED')
                del value['identity']['files'][env[key]]
            elif mutation == 'artifact': env['RAGNAROK_PVM_SIEVE_ARTIFACT'] = 'unrelated.polkavm'
            else: row['parsed']['policy']['actual'] = 'interpreted'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                profile.canonical_guest_plan(value, REVISION, [100000])

    def test_changed_native_activity_cannot_pass(self):
        """A valid process with a different native working set cannot authorize attribution."""
        self.output_change = lambda text: text.replace('sieve,1,12,42,650', 'sieve,1,12,42,651')
        with self.assertRaisesRegex(ValueError, 'native execution or code working set'):
            self.run_profile()
        self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'failed')

    def test_missing_public_call_cannot_pass(self):
        """Successful exit status cannot replace a missing full-state public invocation."""
        self.output_change = lambda text: '\n'.join(line for line in text.splitlines()
            if not line.startswith('SIEVE,ragnarok_prepared,100000,7,'))+'\n'
        with self.assertRaises(ValueError): self.run_profile()
        self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'failed')

    def test_mutated_input_cannot_pass(self):
        """Live byte changes after collection must leave an explicit failed report."""
        member = self.root/'inputs/100000/expected-100000.bin'
        self.mutation = lambda: member.write_bytes(b'changed after collection')
        with self.assertRaises((ValueError, RuntimeError)): self.run_profile()
        self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'failed')

    def test_absent_original_image_never_rebuilds(self):
        """An unavailable measured image must refuse before a replacement could be compiled."""
        Path(next(row for row in self.value['builds'] if row['family'] == 'guest')['binary']).unlink()
        with self.assertRaisesRegex(ValueError, 'Original sealed guest image is absent'):
            self.run_profile()

    def test_another_runner_instance_cannot_supply_profiles(self):
        """Matching architecture alone cannot substitute for the exact canonical runner."""
        self.host['runner'] = {'RUNNER_NAME': 'different physical instance'}
        with self.assertRaisesRegex(ValueError, 'canonical runner instance'):
            self.run_profile()
        self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'failed')

    def test_wrong_recipe_or_input_authority_refuses(self):
        """Source, checked flags, fixture seals and actual backend remain independent gates."""
        for mutation in ('flags', 'input', 'policy', 'scope', 'revision'):
            value = deepcopy(self.value)
            if mutation == 'flags':
                next(row for row in value['builds'] if row['family'] == 'guest')['run']['command'][6] = '--boundchecks:off'
            elif mutation == 'input':
                del value['identity']['files'][str(self.root/'inputs/100000/input-100000.bin')]
            elif mutation == 'policy':
                next(row for row in value['runs'] if row['case_id'] == 'sieve-100000' and
                     row['role'] == 'jit')['parsed']['policy']['actual'] = 'interpreted'
            elif mutation == 'scope': value['scope'] = 'doom'
            else: value['revision'] = 'f'*40
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                profile.canonical_guest_plan(value, REVISION, [100000])


if __name__ == '__main__':
    unittest.main()
