# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Strict continuing frame/state/host parity and intended mutation refusal; actual DOOM runs only on native CI."""
import copy
from pathlib import Path
import sys
import re
import subprocess
import unittest
import tempfile
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_doom_backends import Mismatch, backend_cohort, compare, negative_frames, rgba_frames, observation
import pvm_doom_backends as harness
from workflow_fixtures import event_context, expression, job_condition, job_section, selected_families, commands

ROOT = Path(__file__).resolve().parents[1]


def events(pixel=0):
    """Use a full real-size host frame with an independently chosen BGRX pixel."""
    raw = bytes((pixel, 2, 3, 0))*(640*400)
    return b'\x01'+len(raw).to_bytes(4, 'little')+raw


def observed():
    """Model already executed receipts with distinct adjacent frames and complete independent call identities."""
    return dict(frames=rgba_frames(events(1), 0, 0)+rgba_frames(events(2), 1, 1),
        calls=[dict(state_sha256='state'+str(i), events_sha256='events'+str(i),
                    hosts_sha256='hosts'+str(i), gas=100-i) for i in range(2)])


def eager_output():
    """Model distinct continuing calls with a frozen complete partition and live native counters."""
    snapshot = '1,12,29,1,64,7,10,4,5,1,3'
    lines = ['DOOM_EAGER_PREPARED,'+snapshot]
    for call in range(2):
        lines.extend([f'DOOM_CALL,{call},compiled,compiled,{100-call},1,{call+1},{4*(call+1)},1,1',
                      f'DOOM_EAGER_REUSED,{call},'+snapshot])
    return lines+['DOOM_SEQUENCE_OK,compiled,2']


class DoomBackendTests(unittest.TestCase):
    def test_only_exact_opt_in_selects_the_interpreted_cohort(self):
        """Missing opt-in preserves the existing pair; malformed, reordered or widened cohorts cannot run."""
        self.assertEqual(backend_cohort(''), ('polkavm-interpreted', 'jit'))
        self.assertEqual(backend_cohort('polkavm-interpreted,interpreted'),
                         ('polkavm-interpreted', 'interpreted'))
        self.assertEqual(backend_cohort('polkavm-interpreted,jit,compiled'),
                         ('polkavm-interpreted', 'jit', 'compiled'))
        for requested in ('interpreted', 'jit,interpreted', 'interpreted,polkavm-interpreted',
                          'polkavm-interpreted,interpreted,interpreted',
                          'polkavm-interpreted,interpreted,jit', 'polkavm-interpreted, interpreted',
                          'compiled,polkavm-interpreted,jit', 'polkavm-interpreted,jit, compiled'):
            with self.subTest(requested=requested), self.assertRaisesRegex(ValueError, 'cohort'):
                backend_cohort(requested)

    def test_every_frame_order_state_and_host_stream_is_required(self):
        """A matching final frame cannot excuse a changed earlier frame, CPU/page state or ordered host stream."""
        wanted = observed()
        compare(wanted, copy.deepcopy(wanted), 2)
        for field in ('state_sha256', 'events_sha256', 'hosts_sha256', 'gas'):
            changed = copy.deepcopy(wanted)
            changed['calls'][0][field] = 'wrong'
            with self.subTest(field=field), self.assertRaisesRegex(Mismatch, 'call 0'):
                compare(wanted, changed, 2)
        for field in ('call', 'width', 'height', 'rgba_sha256', 'index'):
            changed = copy.deepcopy(wanted)
            changed['frames'][0][field] = 'wrong'
            with self.subTest(field=field), self.assertRaisesRegex(Mismatch, 'frame 0'):
                compare(wanted, changed, 2)

    def test_real_pixel_rehash_omission_and_order_controls(self):
        """Actual candidate pixel mutation changes its observed SHA; missing/reordered actual receipts also refuse."""
        wanted = observed()
        changed = rgba_frames(events(9), 0, 0)+wanted['frames'][1:]
        rows = negative_frames(wanted, copy.deepcopy(wanted), 2, changed)
        self.assertEqual([r['control'] for r in rows], ['changed-pixel','omitted-frame','reordered-frame'])
        self.assertTrue(all(r['refused'] for r in rows))
        self.assertIn('frame 0', rows[0]['diagnostic'])
        self.assertIn('reordered', rows[2]['diagnostic'])

    def test_truncated_foreign_and_missing_video_cannot_certify_a_frame(self):
        """Only a complete bounded pinned video ABI can generate frame receipts."""
        for data in (b'', events()[:-1], b'\x01\x01\x00\x00\x00x', b'\x09\x00\x00\x00\x00'):
            with self.subTest(prefix=data[:8]), self.assertRaises(ValueError):
                rgba_frames(data, 0, 0)

    def test_interop_native_architectures_own_the_check(self):
        """Master/full/Interop execute native shared backends; focused dispatch avoids unrelated families."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = job_section(text, 'pvm-doom-backends')
        self.assertEqual({row['arch'] for row in selected_families(text, 'pvm-doom-backends', event_context())},
                         {'arm64', 'x86_64'})
        self.assertIn('make check-pvm-doom-backends', commands(section))
        for context in (event_context('push'), event_context('workflow_dispatch', suite='pvm-backends'),
                        event_context('workflow_dispatch', suite='interop'),
                        event_context('workflow_dispatch', suite='full')):
            with self.subTest(context=context):
                self.assertTrue(expression(job_condition(text, 'pvm-doom-backends'), context))

    def test_focused_backends_request_skips_other_interop_workloads(self):
        """Focused dispatch selects both backend architectures without ordinary Interop work."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        context = event_context('workflow_dispatch', suite='pvm-backends')
        self.assertTrue(expression(job_condition(text, 'pvm-doom-backends'), context))
        self.assertFalse(expression(job_condition(text, 'interop'), context))




class NativePolicyReceiptTests(unittest.TestCase):
    def test_eager_construction_is_frozen_and_native_work_advances_on_each_call(self):
        """Only complete positive sealed receipts and live native deltas qualify the explicit eager process."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for call in range(2):
                (folder/f'call-{call}.state').write_bytes(bytes(129+4101))
                (folder/f'call-{call}.events').write_bytes(events(call+1))
                (folder/f'call-{call}.hosts').write_bytes(b'ordered host')
            original = eager_output()
            for architecture in ('arm64', 'x86_64'):
                actual = observation('\n'.join(original), folder, 'compiled', 2, 1, architecture)
                self.assertEqual(actual['construction']['compilation_passes'], 3)
                self.assertEqual([row['actual'] for row in actual['calls']], ['compiled']*2)
                changes = []
                for field, value in ((1, '0'), (5, '0'), (7, '11'), (8, '0'), (11, '0'),
                                     (2, str(2**64)), (3, '１'), (4, '-1')):
                    changed = original.copy()
                    fields = changed[0].split(',')
                    fields[field] = value
                    changed[0] = ','.join(fields)
                    changes.append(changed)
                for line, field, value in ((2, 2, '0'), (4, 3, '99'), (1, 3, 'interpreted'),
                                            (3, 5, '2'), (3, 6, '1'), (3, 7, '4')):
                    changed = original.copy()
                    fields = changed[line].split(',')
                    fields[field] = value
                    changed[line] = ','.join(fields)
                    changes.append(changed)
                changes.extend([original[1:], original[:-1], original+['unexpected']])
                for changed in changes:
                    # Counterfactual copied lines never build or execute an image; each malformed witness must refuse.
                    with self.subTest(architecture=architecture, changed=changed[:1]), self.assertRaises(ValueError):
                        observation('\n'.join(changed), folder, 'compiled', 2, 1, architecture)

    """The real shared driver must report positive native work on both supported Linux CPUs."""
    def test_x86_and_arm_require_actual_jit_activity(self):
        """Matching image bytes alone cannot let an interpreted fallback count as a native default qualification."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            for call in range(2):
                (folder/f'call-{call}.state').write_bytes(bytes(129+4101))
                (folder/f'call-{call}.events').write_bytes(events(call+1))
                (folder/f'call-{call}.hosts').write_bytes(b'host')
            native='DOOM_CALL,0,jit,jit,100,1,1,4,1,1\nDOOM_CALL,1,jit,jit,99,1,2,8,1,1\nDOOM_SEQUENCE_OK,jit,2\n'
            for architecture in ('arm64','x86_64'):
                result=observation(native,folder,'jit',2,1,architecture)
                self.assertEqual(len(result['frames']),2)
                with self.assertRaisesRegex(ValueError,'missing positive'):
                    observation(native.replace(',jit,jit,',',jit,interpreted,'),folder,'jit',2,1,architecture)

    def test_forced_interpreted_requires_native_enabled_image_and_zero_activity_on_both_calls(self):
        """An unavailable generator, substituted engine or any publication/call/operation cannot prove forced interpretation."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for call in range(2):
                (folder/f'call-{call}.state').write_bytes(bytes(129+4101))
                (folder/f'call-{call}.events').write_bytes(events(call+1))
                (folder/f'call-{call}.hosts').write_bytes(b'ordered host')
            lines = ['DOOM_CALL,0,interpreted,interpreted,100,0,0,0,1,1',
                     'DOOM_CALL,1,interpreted,interpreted,99,0,0,0,1,1',
                     'DOOM_SEQUENCE_OK,interpreted,2']
            for architecture in ('arm64', 'x86_64'):
                result = observation('\n'.join(lines), folder, 'interpreted', 2, 1, architecture)
                self.assertEqual([row['actual'] for row in result['calls']], ['interpreted']*2)
                for call in range(2):
                    for field, value in ((3, 'jit'), (3, 'polkavm-interpreted'),
                                         (5, '1'), (6, '1'), (7, '1')):
                        changed = list(lines)
                        fields = changed[call].split(',')
                        fields[field] = value
                        changed[call] = ','.join(fields)
                        with self.subTest(architecture=architecture, call=call, field=field), \
                                self.assertRaisesRegex(ValueError, 'forced interpreter'):
                            observation('\n'.join(changed), folder, 'interpreted', 2, 1, architecture)
                for field in (8, 9):
                    changed = list(lines)
                    fields = changed[1].split(',')
                    fields[field] = '0'
                    changed[1] = ','.join(fields)
                    with self.assertRaisesRegex(ValueError, 'native-enabled'):
                        observation('\n'.join(changed), folder, 'interpreted', 2, 1, architecture)
                for field, value in ((4, '-1'), (5, 'x'), (6, '１'), (7, str(2**64)),
                                     (8, '2'), (9, '2')):
                    changed = list(lines)
                    fields = changed[1].split(',')
                    fields[field] = value
                    changed[1] = ','.join(fields)
                    with self.subTest(field=field, value=value), self.assertRaisesRegex(ValueError, 'invalid DOOM'):
                        observation('\n'.join(changed), folder, 'interpreted', 2, 1, architecture)
            for changed in (lines[:-1], [lines[0], lines[0], lines[2]], [lines[0], lines[2]]):
                with self.assertRaises(ValueError):
                    observation('\n'.join(changed), folder, 'interpreted', 2, 1, 'arm64')


class InterpretedCohortOrchestrationTests(unittest.TestCase):
    """Run the real maintained orchestration with inert child adapters; no native executable is built or launched."""
    def run_cohort(self, selected='', mutation=None):
        """Keep parser/comparator/report/identity behavior live while mocking every compiler and guest process."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root/'build/tests/pvm-doom-backends'
            doom = root/'build/tests/pvm-doom'
            prepared = doom/'prepared'
            prepared.mkdir(parents=True)
            (root/'spec').mkdir()
            for name in ('toolchain.json', 'polkavm-pins.json'):
                (root/'spec'/name).write_text('{"commit":"inert-pin"}')
            (root/'spec/pvm-doom-assets.json').write_text(
                '{"files":{"examples/doom/roms/doom1.wad":"inert-wad"}}')
            (prepared/'tick.input').write_bytes(bytes(16)+(1).to_bytes(4, 'little'))
            (doom/'results.json').write_text(harness.json.dumps(dict(status='checks-passed',
                golden_rgba_sha256=rgba_frames(events(1), 0, 0)[0]['rgba_sha256'],
                linked_sha256='inert-guest')))
            compiler, library = root/'compiler', root/'library'
            compiler.write_bytes(b'inert compiler identity')
            library.write_bytes(b'inert library identity')
            commands, builds = [], []
            # A bad new selector must replace even preexisting successful evidence with an incomplete refusal.
            build.mkdir(parents=True)
            (build/'results.json').write_text('{"status":"passed"}')

            class InertChecks:
                """Only identity bytes and controlled output receipts exist; subprocess execution is separately forbidden."""
                def __init__(self, folder):
                    self.folder = folder

                def build(self, compiler, driver, name, **options):
                    """Record native/runtime defines and create an inert identity file that is never executed."""
                    builds.append((name, options['defines']))
                    binary = self.folder/name
                    binary.write_bytes(b'inert image')
                    return dict(exit_code=0, output=''), binary

                def command(self, args, name, environment=None, timeout=None):
                    """Distinct successive snapshots detect comparison against a restarted or mutated second call."""
                    commands.append((name, args, dict(environment), harness.os.environ.get('PVM_DOOM_BACKENDS')))
                    if name == 'assertions':
                        return dict(exit_code=2, output='DOOM backend assertion control')
                    if name == 'wrong-backend':
                        if environment.get('PVM_DOOM_BACKENDS'):
                            return dict(exit_code=0, output='opt-in interpreted was admitted')
                        return dict(exit_code=2, output='unsupported DOOM comparison backend')
                    if name == 'unavailable-bridge':
                        return dict(exit_code=2, output='DOOM_BACKEND_UNAVAILABLE,polkavm-interpreted,BackendNotBuilt')
                    if name == 'compiled' and mutation == 'absent-eager':
                        return dict(exit_code=2, output='DOOM_BACKEND_UNAVAILABLE,compiled,BackendNotBuilt')
                    folder = Path(environment['RAGNAROK_DOOM_BACKEND_OUTPUT'])
                    lines = []
                    for call in range(2):
                        observed_call = 0 if name in ('interpreted', 'compiled') and mutation == 'restart' and call == 1 else call
                        state = bytes([observed_call])*(129+4101)
                        hosts = f'ordered host {observed_call}'.encode()
                        event_bytes = events(observed_call+1)
                        if name in ('interpreted', 'compiled') and call == 1:
                            if mutation == 'state': state = bytes([99])*(129+4101)
                            elif mutation == 'hosts': hosts = b'changed host order'
                            elif mutation == 'frame': event_bytes = events(9)
                        if name == 'jit' and mutation == 'jit-state' and call == 1:
                            state = bytes([77])*(129+4101)
                        (folder/f'call-{call}.state').write_bytes(state)
                        (folder/f'call-{call}.events').write_bytes(event_bytes)
                        (folder/f'call-{call}.hosts').write_bytes(hosts)
                        counters = f'1,{call+1},{4*(call+1)},1,1' if name in ('jit', 'compiled') else '0,0,0,1,1'
                        lines.append(f'DOOM_CALL,{call},{name},{name},{100-call},{counters}')
                    if name == 'compiled':
                        snapshot = '1,12,29,1,64,7,10,4,5,1,3'
                        reused = [f'DOOM_EAGER_REUSED,{call},'+snapshot for call in range(2)]
                        if mutation == 'eager-change':
                            reused[1] = reused[1].replace(',12,29,', ',13,29,')
                        lines = ['DOOM_EAGER_PREPARED,'+snapshot, lines[0], reused[0], lines[1], reused[1]]
                    return dict(exit_code=0, output='\n'.join(lines)+f'\nDOOM_SEQUENCE_OK,{name},2\n')

            with mock.patch.multiple(harness, ROOT=root, BUILD=build, DOOM=doom,
                    DRIVER=root/'driver.nim', NativeChecks=InertChecks,
                    host_identity=lambda: dict(architecture='arm64'), prepare_doom=lambda **kw: None,
                    build_native=lambda: library, installed=lambda: (compiler, None),
                    native_defines=lambda: ['pvmArm64Jit']), \
                    mock.patch.object(harness.subprocess, 'check_output', return_value='inert-head\n'), \
                    mock.patch.object(harness.subprocess, 'run', side_effect=AssertionError('native process attempted')), \
                    mock.patch.dict(harness.os.environ, dict(GITHUB_ACTIONS='true',
                        PVM_DOOM_CALLS='2', PVM_DOOM_BACKENDS=selected)):
                error = None
                try:
                    harness.run()
                except (ValueError, RuntimeError) as caught:
                    error = caught
                report = harness.json.loads((build/'results.json').read_text())
                return report, commands, builds, error

    def test_default_pair_protocol_processes_and_control_arguments_are_preserved(self):
        """Ordinary CI never expands to forced interpretation and retains its original v1 receipt schema."""
        report, commands, builds, error = self.run_cohort()
        self.assertIsNone(error)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['protocol'], 'doom-shared-backends-v1')
        self.assertNotIn('backends', report)
        self.assertEqual([row[0] for row in commands], ['polkavm-interpreted', 'jit',
            'assertions', 'wrong-backend', 'unavailable-bridge'])
        self.assertEqual(commands[3][1][-2:], ['--pvm-backend', 'interpreted'])
        self.assertEqual(builds, [('doom-backends', ['pvmArm64Jit', 'polkavmRuntime']),
                                 ('doom-no-bridge', ['pvmArm64Jit'])])

    def test_opt_in_uses_one_linked_image_and_clears_selector_only_in_wrong_backend_child(self):
        """Both actual processes retain the selector; its negative child cannot inherit the interpreted allowance."""
        selected = 'polkavm-interpreted,interpreted'
        report, commands, builds, error = self.run_cohort(selected)
        self.assertIsNone(error)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['protocol'], 'doom-shared-interpreted-v1')
        self.assertEqual(report['backends'], selected.split(','))
        self.assertEqual([row[0] for row in commands], ['polkavm-interpreted', 'interpreted',
            'assertions', 'wrong-backend', 'unavailable-bridge'])
        self.assertEqual(commands[0][1][0], commands[1][1][0])
        for name, args, env, parent in commands:
            self.assertEqual(parent, selected)
            self.assertEqual(env['PVM_DOOM_BACKENDS'], '' if name == 'wrong-backend' else selected)
        self.assertEqual(builds[0][1], ['pvmArm64Jit', 'polkavmRuntime'])
        self.assertEqual(len(report['controls']), 6)

    def test_second_call_state_hosts_frames_and_restarted_snapshot_cannot_pass(self):
        """The maintained comparator checks the complete continuing sequence for the new candidate too."""
        for mutation in ('state', 'hosts', 'frame', 'restart'):
            with self.subTest(mutation=mutation):
                report, commands, builds, error = self.run_cohort('polkavm-interpreted,interpreted', mutation)
                self.assertIsInstance(error, Mismatch)
                self.assertEqual(report['status'], 'incomplete')
                self.assertIn('1', report['error'])
                self.assertEqual([row[0] for row in commands], ['polkavm-interpreted', 'interpreted'])

    def test_eager_cohort_keeps_all_three_processes_and_freezes_real_owner_receipts(self):
        """One linked image supplies three continuing engines with the separate eager protocol and unchanged controls."""
        selected = 'polkavm-interpreted,jit,compiled'
        report, commands, builds, error = self.run_cohort(selected)
        self.assertIsNone(error)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['protocol'], 'doom-shared-eager-v1')
        self.assertEqual(report['backends'], selected.split(','))
        self.assertEqual([row[0] for row in commands], ['polkavm-interpreted', 'jit', 'compiled',
            'assertions', 'wrong-backend', 'unavailable-bridge'])
        self.assertEqual(len({row[1][0] for row in commands[:3]}), 1)
        self.assertEqual(builds[0][1], ['pvmArm64Jit', 'polkavmRuntime', 'pvmSourceSealingReceipt'])
        self.assertEqual(builds[1][1], ['pvmArm64Jit'])
        self.assertEqual(len(report['controls']), 6)
        self.assertEqual(report['runs'][2]['observed']['construction']['compilation_passes'], 3)
        for name, args, env, parent in commands:
            self.assertEqual(parent, selected)
            self.assertEqual(env['PVM_DOOM_BACKENDS'], '' if name == 'wrong-backend' else selected)

    def test_eager_cohort_refuses_missing_facility_changed_construction_and_either_wrong_engine_state(self):
        """Neither a missing third process nor correct eager pixels can hide another selected engine's divergence."""
        selected = 'polkavm-interpreted,jit,compiled'
        for mutation in ('absent-eager', 'eager-change', 'jit-state', 'state', 'hosts', 'frame', 'restart'):
            with self.subTest(mutation=mutation):
                report, commands, builds, error = self.run_cohort(selected, mutation)
                self.assertIsNotNone(error)
                self.assertEqual(report['status'], 'incomplete')
                self.assertEqual([row[0] for row in commands], ['polkavm-interpreted', 'jit', 'compiled'])

    def test_invalid_selector_replaces_stale_success_before_build_or_guest_work(self):
        """A malformed request cannot leave an old green report or launch native provisioning/guest work."""
        report, commands, builds, error = self.run_cohort('interpreted,polkavm-interpreted')
        self.assertIsInstance(error, ValueError)
        self.assertEqual(report['status'], 'incomplete')
        self.assertIn('cohort', report['error'])
        self.assertEqual(commands, [])
        self.assertEqual(builds, [])


if __name__ == '__main__':
    unittest.main()
