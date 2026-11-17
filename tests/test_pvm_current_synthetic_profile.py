# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Qualify original host/memory attribution with independent full-process wire and raw return parts."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import pvm_current_synthetic_profile as profile
from pvm_benchmark_report import NAMES
from pvm_performance_fixtures import REVISION
from pvm_performance_synthetic import parse_synthetic
from test_pvm_current_guest_profile import cohort, counters
from test_pvm_invocation_scope import full_cohort
from test_pvm_native_samples import native_wire


def wire(role):
    """Every original owner supplies thirteen checked calls and its own cumulative native log."""
    return full_cohort(role)+native_wire(role)


def host_fallback(text):
    """Keep the JIT policy and complete shared process while one host owner honestly executes checked."""
    text = text.replace('SYNTHETIC_NATIVE,1,3,2,24,168,512,101',
                        'SYNTHETIC_NATIVE,1,3,0,0,0,0,0').replace(
        'SYNTHETIC_POLICY,1,3,jit,1,1,1,jit,2,24,168',
        'SYNTHETIC_POLICY,1,3,jit,1,1,1,interpreted,0,0,0').replace(
        'PVM_NATIVE_COMPILATION,1,synthetic-3,1,101',
        'PVM_NATIVE_COMPILATION,1,synthetic-3,0,0')
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith('PVM_NATIVE_SAMPLE,1,synthetic-3,'):
            lines[index] = ','.join(line.split(',')[:4])+',0,0,0,0,0,0'
    return '\n'.join(lines)+'\n'


def raw_part(number, binary):
    """Independent real-format metadata binds every raw counter body to its process/return ordinal."""
    text = counters(number)
    if number == 0:
        text = text.replace('10 1 2 0', '0 0 0 0')
    metadata = ('pid: 1234\ncmd:  '+str(binary)+'\npart: '+str(number or 144)+
                '\ndesc: Trigger: '+('--dump-after=runPreparedSynthetic_literal' if number else
                                      'Program termination')+'\n')
    return text.replace('positions: line\n', metadata+'positions: line\n')


def synthetic_cohort(root):
    """Seal independent synthetic image/input bytes and both complete original process recipes."""
    value = cohort(root)
    files = value['identity']['files']
    driver = root/'tests/performance/pvm_workload.nim'
    driver.parent.mkdir(parents=True)
    driver.write_text('independent synthetic source')
    files[str(driver)] = hashlib.sha256(driver.read_bytes()).hexdigest()
    binary, fixture = root/'synthetic-image', root/'synthetic-input.bin'
    for path in (binary, fixture):
        path.write_bytes(path.name.encode())
        files[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    build, = [row for row in value['builds'] if row['family'] == 'synthetic']
    build.update(binary=str(binary), binary_sha256=files[str(binary)])
    build['run']['command'] = [str(root/'compiler/nimony'), 'c', '--mm:arc', '--cc:clang',
        '-d:release', '--opt:speed', '--boundchecks:on', '--passC:-flto=thin',
        '--passL:-flto=thin', '--passL:-fuse-ld=lld', '-d:pvmX86Jit',
        '--passC:-I'+str(root/'tests/performance'), '--passC:-I'+str(root/'native/pvm_jit'),
        '--nimcache:'+str(root/'synthetic-cache'), '--out:'+str(binary), str(driver)]
    for control in value['controls']:
        if control['case_id'] == 'synthetic' and control['role'] != 'reference':
            control['run']['command'][0] = str(binary)
    for role in ('interpreted', 'jit'):
        parsed = parse_synthetic(wire(role), role, require_full=True)
        for row in value['runs']:
            if row['role'] == role and row['case_id'] in NAMES:
                row['parsed'] = deepcopy(parsed[row['case_id']])
                row['run'].update(command=[str(binary)], benchmark_environment=dict(
                    RAGNAROK_PVM_BACKEND=role, RAGNAROK_PVM_PERFORMANCE='1',
                    RAGNAROK_PVM_BENCHMARK=str(fixture), RAGNAROK_PVM_PRICING='prepared',
                    RAGNAROK_PVM_BENCH_ASSERT_PROBE='0'))
        for order in (0, 1):
            # The real runner copies one identical complete process receipt to its eleven case rows.
            shared = next(row['run'] for row in value['runs'] if
                          (row['case_id'], row['role'], row['order']) == (NAMES[0], role, order))
            for row in value['runs']:
                if row['role'] == role and row['order'] == order and row['case_id'] in NAMES:
                    row['run'] = deepcopy(shared)
    return value


class CurrentSyntheticProfile(unittest.TestCase):
    """No executable, compiler or network is reachable from these canonical qualification witnesses."""

    def setUp(self):
        """Own isolated original image, source, fixture and report bytes for each qualification attempt."""
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.value = synthetic_cohort(self.root)
        self.host = deepcopy(self.value['identity']['host'])
        self.folder = self.root/'profiles'
        self.path = self.root/'cohort.json'
        self.processes = []
        self.change = lambda text: text
        self.mutate = None
        self.omit = None
        self.raw_change = lambda number, text: text

    def run_profile(self):
        """Exercise real image guards, all-case parsing, counter qualification and numbered raw selection."""
        self.path.write_text(json.dumps(self.value))

        def command(arguments, name, **options):
            """An inert retained image returns all owners, with distinct costs identifying every raw part."""
            if '--tool=callgrind' in arguments:
                env = options['environment']
                self.processes.append((list(map(str, arguments)), env))
                role = env['RAGNAROK_PVM_BACKEND']
                target = Path(next(arg.split('=', 1)[1] for arg in arguments
                                   if str(arg).startswith('--callgrind-out-file=')))
                for index in range(1, 144):
                    if index != self.omit:
                        target.with_name(target.name+'.'+str(index)).write_text(
                            self.raw_change(index, raw_part(index, self.root/'synthetic-image')))
                target.write_text(self.raw_change(0, raw_part(0, self.root/'synthetic-image')))
                text = self.change(wire(role))
                if self.mutate:
                    self.mutate()
            else:
                text = 'valgrind-3.22.0\n' if name == 'synthetic-version' else (
                    '0000 T runPreparedSynthetic_literal\n' if name == 'synthetic-symbols' else '')
            return dict(command=list(map(str, arguments)), exit_code=0, output=text, log=name+'.log')

        with patch.dict(profile.os.environ, GITHUB_ACTIONS='true'), \
                patch.object(profile, 'host_identity', return_value=self.host), \
                patch.object(profile, 'canonical_source_identity', return_value={'revision': REVISION}), \
                patch.object(profile, 'canonical_tooling_seals', return_value={}), \
                patch.object(profile, 'calibrate_scope'), \
                patch.object(profile.NativeChecks, 'command', side_effect=command):
            return profile.profile_current_synthetic(self.path, REVISION, self.folder)

    def test_two_original_processes_keep_every_case_and_exact_return_parts(self):
        """Host/memory costs come from their original case positions, with all other calls still present."""
        report = self.run_profile()
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(len(self.processes), 2)
        self.assertEqual([(row['role'], row['case']) for row in report['profiles']],
                         [(role, name) for role in ('interpreted', 'jit') for name in NAMES])
        for row in report['profiles']:
            index = NAMES.index(row['case'])
            self.assertEqual((row['cold']['Ir'], row['reused']['Ir']), (index*13+1, index*13+13))
            self.assertEqual(row['checked_calls'], 143)
            self.assertEqual(len(row['profile_hashes']), 144)
            self.assertEqual(row['native_comparison']['measured_samples'], [0, *range(3, 13)])
            self.assertNotIn('invocation', row)
        for arguments, environment in self.processes:
            self.assertIn('--fair-sched=yes', arguments)
            self.assertEqual(arguments[-1], str(self.root/'synthetic-image'))
            self.assertEqual(set(environment) & {'RAGNAROK_PVM_GUEST', 'RAGNAROK_PVM_CASE'}, set())

    def test_missing_unselected_call_or_middle_raw_part_refuses(self):
        """No apparently useful host/memory result can hide a skipped call elsewhere in the process."""
        for broken in ('wire', 'part'):
            if broken == 'wire':
                self.change = lambda text: text.replace('SYNTHETIC_SAMPLE,1,5,4,1004,2004\n', '')
            else:
                self.change = lambda text: text
                self.omit = 70
            with self.subTest(broken=broken), self.assertRaises(ValueError):
                self.run_profile()
            self.assertEqual(json.loads((self.folder/'synthetic-results.json').read_text())['status'], 'failed')

    def test_jit_policy_host_fallback_stays_explicit(self):
        """A zero-native host owner is useful attribution, without pretending it executed native code."""
        parsed = parse_synthetic(host_fallback(wire('jit')), 'jit', require_full=True)
        for row in self.value['runs']:
            if row['case_id'] == NAMES[3] and row['role'] == 'jit':
                row['parsed'] = deepcopy(parsed[NAMES[3]])
        self.change = host_fallback
        report = self.run_profile()
        selected, = [row for row in report['profiles'] if row['case'] == NAMES[3] and row['role'] == 'jit']
        self.assertEqual(selected['policy']['actual'], 'interpreted')
        self.assertEqual(selected['actual_by_phase'], dict(cold='interpreted', reused='interpreted'))

    def test_measured_work_change_cannot_hide_behind_valid_terminal_aggregate(self):
        """One redistributed operation in a later owner invalidates that policy's attribution."""
        self.change = lambda text: text.replace('synthetic-8,4,2,8,56,512,4,0',
                                               'synthetic-8,4,2,8,57,512,4,0')
        with self.assertRaisesRegex(ValueError, 'native execution or code working set'):
            self.run_profile()
        result = json.loads((self.folder/'synthetic-results.json').read_text())
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(len(result['profiles']), 21)
        self.assertEqual([(row['case'], row['role']) for row in result['refusals']], [(NAMES[8], 'jit')])
        self.assertEqual(result['profiles'][-1]['case'], NAMES[-1])
        for key in ('canonical_native_samples', 'profiled_native_samples'):
            self.assertEqual(len(result['refusals'][0][key]['samples']), 13)

    def test_changed_fixture_or_image_refuses_before_qualification(self):
        """Live sealed inputs are guarded around every collector command, not just at planning time."""
        for name in ('synthetic-image', 'synthetic-input.bin'):
            original = (self.root/name).read_bytes()
            self.mutate = lambda: (self.root/name).write_bytes(b'changed')
            with self.subTest(name=name), self.assertRaises(Exception):
                self.run_profile()
            (self.root/name).write_bytes(original)

    def test_case_process_recipe_and_historical_missing_logs_refuse(self):
        """One owner cannot borrow another process, filtered inputs or invented historical samples."""
        original = deepcopy(self.value)
        for broken in ('recipe', 'filter', 'samples'):
            self.value = deepcopy(original)
            row = next(row for row in self.value['runs'] if
                       (row['case_id'], row['role'], row['order']) == (NAMES[8], 'jit', 0))
            if broken == 'recipe':
                row['run']['command'].append('selected-case')
            elif broken == 'filter':
                row['run']['benchmark_environment']['RAGNAROK_PVM_CASE'] = NAMES[8]
            else:
                row['parsed']['diagnostics']['scope_observations'].pop('native_sample')
                row['parsed']['diagnostics']['scope_observations'].pop('native_observations')
            with self.subTest(broken=broken), self.assertRaises(ValueError):
                self.run_profile()
        self.assertEqual(self.processes, [])

    def test_embedded_identity_and_complete_event_columns_bind_every_part(self):
        """Intact swaps, foreign processes/triggers, missing events and leftover branch work all refuse."""
        for broken in ('swapped', 'pid', 'command', 'scope', 'events', 'termination'):
            def change(number, text):
                """Change one independent identity dimension while retaining all 143 file names."""
                if broken == 'swapped' and number in (1, 40):
                    return raw_part(40 if number == 1 else 1, self.root/'synthetic-image')
                if number == 40:
                    if broken == 'pid': return text.replace('pid: 1234', 'pid: 5678')
                    if broken == 'command': return text.replace('cmd:  ', 'cmd:  foreign-')
                    if broken == 'scope': return text.replace('runPreparedSynthetic_literal', 'other')
                    if broken == 'events': return text.replace('events: Ir Bc Bcm Bi Bim', 'events: Ir').replace(' 10 1 2 0', '')
                if broken == 'termination' and number == 0:
                    return text.replace('0 0 0 0 0', '0 1 0 0 0')
                return text
            self.raw_change = change
            with self.subTest(broken=broken), self.assertRaises(ValueError):
                self.run_profile()
            result = json.loads((self.folder/'synthetic-results.json').read_text())
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['profiles'], [])

    def test_one_case_cannot_claim_a_different_original_process(self):
        """Equal command/environment cannot merge distinct canonical process receipts."""
        row = next(row for row in self.value['runs'] if
                   (row['case_id'], row['role'], row['order']) == (NAMES[3], 'jit', 0))
        row['run']['log'] = 'different-original-process.log'
        with self.assertRaisesRegex(ValueError, 'invocation recipe'):
            self.run_profile()
        self.assertEqual(self.processes, [])
