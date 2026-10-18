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
        names = ('pvm_gas', 'store', 'authorization', 'history', 'signing', 'entropy', 'validator', 'ticket', 'sealer')
        keys = ('pvm_gas_fixture', 'store_replay_fixture', 'authorization_stf_fixture', 'history_stf_fixture',
                'signing_domain_fixture', 'entropy_stf_fixture', 'validator_stf_fixture',
                'ticket_stf_fixture', 'sealer_stf_fixture')
        order = []
        with ExitStack() as stack:
            runtime = stack.enter_context(patch.object(native_preparation, 'unit_runtime_fixtures', return_value={'runtime': 'manifest'}))
            for name in names:
                # Each provider returns distinct manifest/evidence objects; assembly must retain both.
                def prepare(folder, name=name):
                    order.append(name)
                    return {name: folder/name}, {'fixture_sha256': name}
                stack.enter_context(patch.object(native_preparation, 'unit_'+name+'_fixture', side_effect=prepare))
            fixtures, evidence = native_preparation.prepare_unit_fixtures(Path('/fixture'), 'certs', 'wires', 'reload')
        runtime.assert_called_once_with('certs', 'wires', 'reload')
        self.assertEqual(order, list(names))
        self.assertEqual(list(fixtures), ['runtime', *names])
        self.assertEqual(evidence, {key: {'fixture_sha256': name} for key, name in zip(keys, names)})


# Direct execution shares the discovery test cases.
if __name__ == '__main__':
    unittest.main()
