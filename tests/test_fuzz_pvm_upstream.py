# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Test source inventory, exact generator reuse and distinct CI ownership, without running native suites."""
import hashlib
import unittest
from unittest.mock import patch
from harness_fixtures import temporary_folder, make_plan
from workflow_fixtures import event_context, selected_families, family_section, commands, artifact_paths
import fuzz_pvm_upstream as fuzz


class UpstreamFuzzToolTests(unittest.TestCase):
    """Protocol observations remain Nim assertions; Python checks orchestration and provenance only."""

    def test_complete_pinned_inventory(self):
        """The upstream manifest and original CI list must agree, including Linux-only targets."""
        inventory = fuzz.inventory()
        self.assertEqual(len(inventory['targets']), 7)
        self.assertTrue(fuzz.LINUX_ONLY < set(inventory['targets']))
        self.assertIn('fuzz_polkavm', inventory['targets'])

    def test_generator_slice_and_targets_stay_unchanged(self):
        """Only generated dependency paths relocate; no private hook or edited upstream Rust enters the bridge."""
        with temporary_folder() as folder, patch.object(fuzz, 'BUILD', folder):
            manifest = fuzz.prepare_reference()
            copied = manifest.parent
            original = fuzz.UPSTREAM/'fuzz'
            for source in sorted((original/'fuzz_targets').glob('*.rs')):
                self.assertEqual(source.read_bytes(), (copied/'fuzz_targets'/source.name).read_bytes())
            for name in ['Cargo.lock', 'rust-toolchain.toml']:
                self.assertEqual((original/name).read_bytes(), (copied/name).read_bytes())
            source = (original/'fuzz_targets/fuzz_polkavm.rs').read_text()
            prefix = source[source.index('#[derive(Arbitrary, Debug)]'):source.index('fn build_program_blob(')]
            self.assertIn(prefix, (copied/'bridge.rs').read_text())
            self.assertNotIn('_for_testing', (copied/'bridge.rs').read_text())
            self.assertEqual(manifest.read_text().count('name = "ragnarok-jam-bridge"'), 1)
            fuzz.prepare_reference()
            self.assertEqual(manifest.read_text().count('name = "ragnarok-jam-bridge"'), 1)

    def test_supplemental_seeds_are_stable_and_bounded(self):
        """Saved original inputs have content identities and stable authored seed provenance."""
        with temporary_folder() as folder:
            first = fuzz.seed_inputs(folder/'first')
            second = fuzz.seed_inputs(folder/'second')
            self.assertEqual([p.name for p in first], [p.name for p in second])
            self.assertEqual(len(first), 256)
            for path in first:
                self.assertLessEqual(path.stat().st_size, 4096)
                self.assertEqual(path.name, hashlib.sha256(path.read_bytes()).hexdigest())

    def test_ci_separates_upstream_and_native_verdicts(self):
        """All Linux targets and the bridge run in their own job, retaining raw failures even after failure."""
        text = (fuzz.ROOT/'.github/workflows/ci.yml').read_text()
        for event in (event_context(), event_context('workflow_dispatch',suite='fuzz-pvm'),
                      event_context('workflow_dispatch',suite='fuzz'),
                      event_context('pull_request','labeled','ci:fuzz'),
                      event_context('workflow_dispatch',suite='full')):
            with self.subTest(event=event):
                section=family_section(text,'pvm-fuzz','pvm',context=event)
                self.assertIn('make fuzz-pvm-upstream',commands(section))
                self.assertIn('build/pvm-upstream-fuzz/artifacts/',artifact_paths(section))
                self.assertFalse(section.get('continue-on-error',False))
                self.assertFalse(any(step.get('continue-on-error',False) for step in section['steps']))
        self.assertFalse(selected_families(text,'pvm-fuzz',event_context('pull_request','synchronize')))
        plan=make_plan('fuzz-pvm-upstream')
        install='rustup toolchain install '+fuzz.NIGHTLY+' --profile minimal'
        self.assertIn(install,plan)
        self.assertLess(plan.index(install),plan.index('tools/fuzz_pvm_upstream.py'))

    def test_reducer_retains_same_profile_assertion_and_original_bytes(self):
        """Reduction is capped, preserves native assertion identity and emits replayable retained bytes."""
        with temporary_folder() as folder:
            source = folder/'original.raw'
            source.write_bytes(b'abcdefgh')

            def command(arguments, name, output, environment, timeout):
                # Model only orchestration; real guest properties stay in the native module.
                if arguments[0].name == 'ragnarok-jam-bridge':
                    frames = arguments[2]
                    frames.mkdir()
                    (frames/'case-0.bin').write_bytes(b'reference-frame')
                    return dict(exit_code=0, timed_out=False, output='case\tbridged\t3\tnone\t1,51,0\n')
                return dict(exit_code=1, timed_out=False, output='[Assertion Failure] upstream gas mismatch', log='native.log')

            with patch.object(fuzz, 'BUILD', folder), patch.object(fuzz, 'inventory'), patch.object(fuzz, 'run_group', side_effect=command) as run:
                self.assertEqual(fuzz.replay_raw(source, minimize=True), 1)
                self.assertEqual(len((folder/'reproduction/retained.raw').read_bytes()), 1)
                self.assertEqual((folder/'reproduction/retained.bin').read_bytes(), b'reference-frame')
                self.assertLessEqual(run.call_count, 130)

    def test_reducer_rejects_local_timeout_and_nonsemantic_failure(self):
        """Reference/native process errors cannot become minimized guest mismatches."""
        with temporary_folder() as folder:
            source = folder/'original.raw'
            source.write_bytes(b'input')
            for timed_out in [False, True]:
                with patch.object(fuzz, 'BUILD', folder), patch.object(fuzz, 'inventory'), patch.object(
                        fuzz, 'run_group', return_value=dict(exit_code=1, timed_out=timed_out, output='setup failure', log='reference.log')):
                    with self.assertRaisesRegex(ValueError, 'Reference replay failed'):
                        fuzz.replay_raw(source, minimize=True)
                self.assertFalse((folder/'reproduction/retained.raw').exists())
