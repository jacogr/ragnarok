# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check shared preparation boundaries without invoking native builds or using stale fixtures.

Exposes NativePreparationHarness for unittest discovery; test methods exercise the stated
contracts.
"""
from contextlib import ExitStack
import hashlib
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from harness_fixtures import temporary_folder

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import native_preparation
import native_fixtures


# Both supported entry points rely on these preparation contracts and propagate all provider failures.
class NativePreparationHarness(unittest.TestCase):
    # Every reload changes only its first byte; evidence hashes the actual original and candidate files.
    def test_reload_bytes_and_evidence(self):
        with temporary_folder() as folder:
            wires = folder/'wires'
            wires.mkdir()
            for index in range(8):
                # Distinct lengths and first bytes expose replacement, truncation and wrong-child mistakes.
                (wires/f'{index}.bin').write_bytes(bytes([index])* (index+1))
            with patch('test_integration.BUILD', folder), patch('test_integration.corpus', return_value=(wires, ['keys'])):
                original, reload, evidence = native_preparation.prepare_integration(folder)
            self.assertEqual(original, wires)
            self.assertEqual(evidence['keys'], ['keys'])
            for index in range(8):
                # The independently generated corpus remains immutable while all candidates are prepared.
                before = bytes([index])*(index+1)
                after = bytes([index ^ 128])+before[1:]
                self.assertEqual((wires/f'{index}.bin').read_bytes(), before)
                self.assertEqual((reload/f'{index}.bin').read_bytes(), after)
                self.assertEqual(evidence['original'][str(index)], hashlib.sha256(before).hexdigest())
                self.assertEqual(evidence['reload'][str(index)], hashlib.sha256(after).hexdigest())

    # Provider order and library/evidence identities must stay consistent across entry points.
    def test_prepared_libraries(self):
        order = []
        def crypto(folder):
            # Both crypto profiles come from the same independent preparation call.
            order.append(('crypto', folder))
            return 'crypto', 'observer', {'crypto': 'evidence'}
        def bandersnatch(folder):
            # Keep real and observed Rust library identities distinct.
            order.append(('bandersnatch', folder))
            return 'bs', 'bs-observer', {'bs': 'evidence'}
        def quic():
            # QUIC preparation owns its certificate workspace and takes no caller folder.
            order.append(('quic', None))
            return 'quic', 'certificates', {'quic': 'evidence'}
        with patch('nimony_crypto.prepare', side_effect=crypto), patch('bandersnatch_native.prepare', side_effect=bandersnatch), patch('nimony_quic.prepare', side_effect=quic):
            libraries, certificates, evidence = native_preparation.prepare_libraries(Path('/fixture'))
        self.assertEqual(order, [('crypto', Path('/fixture')), ('bandersnatch', Path('/fixture')), ('quic', None)])
        self.assertEqual(libraries, dict(crypto='crypto', observer='observer', bandersnatch='bs', bandersnatch_observer='bs-observer', quic='quic'))
        self.assertEqual(certificates, 'certificates')
        self.assertEqual(evidence, dict(crypto_native={'crypto': 'evidence'}, bandersnatch_native={'bs': 'evidence'}, quic_native={'quic': 'evidence'}))

    # Failed preparation must stop immediately, without allowing later providers to supply partial success.
    def test_library_failure_stops_preparation(self):
        with patch('nimony_crypto.prepare', side_effect=RuntimeError('prepare failed')):
            with patch('bandersnatch_native.prepare') as bandersnatch, patch('nimony_quic.prepare') as quic:
                with self.assertRaisesRegex(RuntimeError, 'prepare failed'):
                    native_preparation.prepare_libraries(Path('/fixture'))
                bandersnatch.assert_not_called()
                quic.assert_not_called()

    # A later provider failure must not discard the standalone runner's already completed evidence.
    def test_completed_stage_is_recorded_before_failure(self):
        recorded = []
        with patch('nimony_crypto.prepare', return_value=('crypto', 'observer', {'ready': True})):
            with patch('bandersnatch_native.prepare', side_effect=RuntimeError('later failure')):
                with self.assertRaisesRegex(RuntimeError, 'later failure'):
                    native_preparation.prepare_libraries(Path('/fixture'), lambda name, value: recorded.append((name, value)))
        self.assertEqual(recorded, [('crypto_native', {'ready': True})])

    # Preserve feature order, independent evidence names and all consumers when combining shared fixtures.
    def test_fixture_assembly(self):
        names = ('pvm_step', 'pvm_gas', 'store', 'authorization', 'history', 'signing', 'entropy', 'validator', 'ticket', 'sealer')
        keys = ('pvm_step_fixture', 'pvm_gas_fixture', 'store_replay_fixture', 'authorization_stf_fixture', 'history_stf_fixture',
                'signing_domain_fixture', 'entropy_stf_fixture', 'validator_stf_fixture',
                'ticket_stf_fixture', 'sealer_stf_fixture')
        order = []
        plan = native_preparation.PROVIDERS.plan('root')
        with ExitStack() as stack:
            runtime = stack.enter_context(patch.object(native_preparation, 'unit_runtime_fixtures', return_value={'runtime': 'manifest'}))
            for provider in plan:
                # Mock every declared stage, including newly added ones, so this never invokes real generators.
                def prepare(folder, name=provider.name):
                    order.append(name)
                    return {name: folder/name}, {'fixture_sha256': name}
                stack.enter_context(patch.object(native_fixtures, provider.function, side_effect=prepare))
            fixtures, evidence = native_preparation.prepare_unit_fixtures(Path('/fixture'), 'certs', 'wires', 'reload')
        runtime.assert_called_once_with('certs', 'wires', 'reload')
        self.assertEqual([name for name in order if name in names], list(names))
        self.assertEqual(list(fixtures), ['runtime', *order])
        self.assertEqual({key: evidence[key] for key in keys},
                         {key: {'fixture_sha256': name} for key, name in zip(keys, names)})
        self.assertEqual(set(evidence), {provider.evidence[0] for provider in plan})

    # Required profiles select provider families before native builds and expose only requested library names.
    def test_selected_library_providers(self):
        cases = [([], (), {}), (['observer'], ('crypto',), {'observer': 'observed'}),
                 (['bandersnatch'], ('bs',), {'bandersnatch': 'bs'}),
                 (['quic'], ('quic',), {'quic': 'quic'}),
                 (['bandersnatch_observer', 'crypto'], ('crypto', 'bs'),
                  {'bandersnatch_observer': 'bs-observed', 'crypto': 'crypto'})]
        for required, expected, wanted in cases:
            # Provider calls and retained evidence independently reveal accidental unrelated setup.
            with self.subTest(required=required), patch('nimony_crypto.prepare',
                    return_value=('crypto', 'observed', {'id': 'crypto'})) as crypto, patch(
                    'bandersnatch_native.prepare', return_value=('bs', 'bs-observed', {'id': 'bs'})) as bs, patch(
                    'nimony_quic.prepare', return_value=('quic', 'certs', {'id': 'quic'})) as quic:
                recorded = []
                libraries, certificates, evidence = native_preparation.prepare_libraries(
                    Path('/fixture'), lambda name, value: recorded.append((name, value)), required=required)
                self.assertEqual(libraries, wanted)
                self.assertEqual(tuple(name for name, mock in [('crypto', crypto), ('bs', bs), ('quic', quic)] if mock.called), expected)
                self.assertEqual(certificates, 'certs' if 'quic' in expected else None)
                self.assertEqual(dict(recorded), evidence)
                self.assertEqual(len(evidence), len(expected))

    # Bad dependency names fail before providers can publish evidence or create foreign resources.
    def test_unknown_library_provider(self):
        with patch('nimony_crypto.prepare') as crypto, patch('bandersnatch_native.prepare') as bs, patch('nimony_quic.prepare') as quic:
            with self.assertRaisesRegex(ValueError, 'Unknown native library'):
                native_preparation.prepare_libraries(Path('/fixture'), required=['typo'])
            for provider in (crypto, bs, quic):
                # One provider must not run merely because a different name was valid.
                provider.assert_not_called()

    # Every prepared suite has exactly one selection, independently checked against the suite requirements.
    def test_selected_fixture_coverage_and_isolation(self):
        import native_fixtures
        from native_requirements import NATIVE_REQUIREMENTS
        selected = {suite: profile for suite, profile in NATIVE_REQUIREMENTS.items() if profile['prepared']}
        for suite, profile in selected.items():
            # Every requirement resolves to exactly its named provider, without an independent consumer list.
            with self.subTest(suite=suite), ExitStack() as stack:
                providers = {name: stack.enter_context(patch.object(native_fixtures, entry.function))
                             for name, entry in native_preparation.PROVIDERS.providers.items()}
                manifests = {name: ('env', Path('/fixture')/name, ())
                             for name, record in selected.items() if record['provider'] == profile['provider']}
                providers[profile['provider']].return_value = manifests, {'sha': suite}
                stack.enter_context(patch.object(native_preparation, 'prepare_integration',
                                                return_value=('wires', 'reload', {'sha': suite})))
                recorded = []
                fixtures, evidence = native_preparation.prepare_selected_fixture(Path('/fixture'), suite,
                    certificates='certs', record=lambda name, value: recorded.append((name, value)))
                self.assertEqual(fixtures, {suite: manifests[suite]})
                self.assertEqual(evidence, {'sha': suite})
                self.assertEqual(recorded, [('selected_unit_fixture', evidence)])
                self.assertEqual([name for name, provider in providers.items() if provider.called],
                                 [profile['provider']])

    # Omitted providers and missing returned manifests cannot reuse an unrelated or stale fixture.
    def test_selected_fixture_refusal(self):
        import native_fixtures
        with self.assertRaisesRegex(ValueError, 'No selected fixture provider'):
            native_preparation.prepare_selected_fixture(Path('/fixture'), 'no-such-suite')
        with patch.object(native_fixtures, 'unit_pvm_gas_fixture', return_value=({}, {})):
            with self.assertRaisesRegex(ValueError, 'Missing selected fixture manifest'):
                native_preparation.prepare_selected_fixture(Path('/fixture'), 'pvm_gas')
        with patch.object(native_fixtures, 'unit_pvm_gas_fixture', side_effect=RuntimeError('fixture refused')):
            with self.assertRaisesRegex(RuntimeError, 'fixture refused'):
                native_preparation.prepare_selected_fixture(Path('/fixture'), 'pvm_gas')

    # Partition preparation invokes a shared feature provider once and returns only requested manifests.
    def test_partition_fixture_provider_sharing(self):
        names = ['accumulation_service', 'accumulation_skip', 'accumulation_complete_batch']
        manifests = {name: ('fixture', Path('/fresh')/name, ()) for name in names[:2]}
        with patch.object(native_preparation, '_selected_fixture_provider',
                          return_value=(manifests, {'fresh': True})) as provider:
            fixtures, evidence = native_preparation.prepare_partition_fixtures(Path('/fixture'), names)
        provider.assert_called_once_with(Path('/fixture'), names[0], None)
        self.assertEqual(fixtures, manifests)
        self.assertEqual(evidence, {names[0]: {'fresh': True}})
        with patch.object(native_preparation, '_selected_fixture_provider', return_value=({}, {})):
            with self.assertRaisesRegex(ValueError, 'Missing partition fixture manifests'):
                native_preparation.prepare_partition_fixtures(Path('/fixture'), names)

    # A partition reuses already-prepared integration bytes instead of rebuilding the same CE driver.
    def test_partition_integration_reuse(self):
        manifest = (None, {}, ())
        with patch.object(native_fixtures, 'unit_integration_fixture',
                          return_value=({'quic_integration': manifest}, {'files': {}})) as provider, patch.object(
                native_preparation, 'prepare_integration') as prepare:
            fixtures, _ = native_preparation.prepare_partition_fixtures(
                Path('/fixture'), ['quic_integration'], integration=('wires', 'reload'))
        provider.assert_called_once_with(Path('/fixture'), integration=('wires', 'reload'))
        prepare.assert_not_called()
        self.assertEqual(fixtures, {'quic_integration': manifest})

    # QUIC transport hashes only certificates, while integration hashes all original/reload children without certificates.
    def test_selected_quic_fixture_isolation(self):
        with temporary_folder() as folder:
            for name in ('a.cert.pem', 'a.key.pem'):
                # Distinct literal bytes expose omitted or substituted inputs in the returned manifest.
                (folder/name).write_bytes(name.encode())
            fixtures, evidence = native_preparation.prepare_selected_fixture(folder, 'quic_transport', folder)
            self.assertEqual(set(fixtures), {'quic_transport'})
            self.assertEqual(len(fixtures['quic_transport'][2]), 2)
            self.assertEqual(len(evidence['files']), 2)
            # Block downloads require both fresh transport identities and the frozen independent report.
            block, observed = native_preparation.prepare_selected_fixture(folder, 'application_block_download', folder)
            self.assertEqual(set(block), {'application_block_download'})
            self.assertEqual(len(block['application_block_download'][2]), 3)
            self.assertEqual(set(block['application_block_download'][1]),
                             {'RAGNAROK_TEST_CERT', 'RAGNAROK_TEST_KEY', 'RAGNAROK_STATE_REPORT'})
            self.assertEqual(len(observed['files']), 3)
            original, reload = folder/'original', folder/'reload'
            original.mkdir(); reload.mkdir()
            for index in range(8):
                # Later CE siblings remain covered rather than just the first file in each directory.
                (original/f'{index}.bin').write_bytes(bytes([index]))
                (reload/f'{index}.bin').write_bytes(bytes([index+1]))
            with patch.object(native_preparation, 'prepare_integration', return_value=(original, reload, {'fresh': True})) as prepare:
                selected, evidence = native_preparation.prepare_selected_fixture(folder, 'quic_integration')
            prepare.assert_called_once_with(folder)
            self.assertEqual(set(selected), {'quic_integration'})
            self.assertEqual(len(selected['quic_integration'][2]), 16)
            self.assertEqual(evidence, {'fresh': True})


# Direct execution shares the discovery test cases.
if __name__ == '__main__':
    unittest.main()
