"""Reject inventory integration mistakes before native provisioning or execution."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from check_inventory import validate_registration
from failure_checks import FAILURE_SUITES, load_suites


# Exercise invalid declarations and real command wiring without substituting native verdicts.
class InventoryPreflight(unittest.TestCase):
    # Misspellings, missing sources and unsupported profiles must fail even when case counts still match.
    def test_invalid_suite_fields_and_profiles(self):
        valid = FAILURE_SUITES['validator_rotation']
        mutations = [('typo', True), ('source', 'tests/native/missing-driver.nim'),
                     ('source', '../outside.nim'), ('crypto_library', 'quic'),
                     ('quic_library', 'crypto'), ('native_libraries', ['unknown']),
                     ('native_libraries', 'bandersnatch'), ('defines', ['--unchecked']),
                     ('build_name', '../escaped'), ('cases', {})]
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for field, value in mutations:
                # Each mutation isolates an error that otherwise could survive JSON parsing.
                suite = copy.deepcopy(valid)
                suite[field] = value
                (folder/'validator_rotation.json').write_text(json.dumps(suite))
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    load_suites(folder)

    # Defaults must expand from actual identity fields; explicit case typos cannot be ignored.
    def test_invalid_case_fields_and_defaults(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for field, value in (('diagnostic_typo', 'contract'), ('arguments', 'default'),
                                  ('identity', {}), ('diagnostic', ' ')):
                # Valid suite metadata cannot compensate for a malformed individual probe.
                suite = copy.deepcopy(FAILURE_SUITES['validator_rotation'])
                suite['cases'][0][field] = value
                (folder/'validator_rotation.json').write_text(json.dumps(suite))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    load_suites(folder)
            (folder/'validator_rotation.json').unlink()
            suite = copy.deepcopy(FAILURE_SUITES['bounded'])
            suite['name_template'] = '{unknown_identity_field}'
            (folder/'bounded.json').write_text(json.dumps(suite))
            with self.assertRaisesRegex(ValueError, 'Invalid defaults in bounded'):
                load_suites(folder)

    # Different families must not overwrite one another's build or probe logs.
    def test_cross_family_log_collisions(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            first = copy.deepcopy(FAILURE_SUITES['validator_rotation'])
            (folder/'validator_rotation.json').write_text(json.dumps(first))
            for collision in ('build', 'probe'):
                # Keep family identities and independent case counts valid while colliding only log names.
                second = copy.deepcopy(FAILURE_SUITES['ticket_state'])
                if collision == 'build':
                    second['build_name'] = first['build_name']
                else:
                    second['cases'][0]['name'] = first['cases'][0]['name']
                (folder/'ticket_state.json').write_text(json.dumps(second))
                with self.subTest(collision=collision), self.assertRaisesRegex(ValueError, 'Duplicate failure log'):
                    load_suites(folder)

    # Deleted files, unscheduled additions, duplicate calls and computed names cannot silently alter coverage.
    def test_registration_mismatches(self):
        suites = {'first': {}, 'second': {}}
        def runner(calls):
            # Only syntax is inspected; deliberately inert arguments must never be executed.
            return 'def run_failures():\n'+''.join('    run_failure_suite(None, '+name+')\n' for name in calls)
        validate_registration(suites, runner(["'second'", "'first'"]))
        for names in (["'first'"], ["'first'", "'second'", "'third'"],
                      ["'first'", "'second'", "'first'"], ['computed_name']):
            # File order does not schedule probes, but each declared family requires one literal call.
            with self.subTest(names=names), self.assertRaises(ValueError):
                validate_registration(suites, runner(names))
        with tempfile.TemporaryDirectory() as temporary, self.assertRaisesRegex(ValueError, 'No failure suites'):
            load_suites(Path(temporary))

    # The public preflight command must succeed without scheduling dependency setup or a native compiler.
    def test_standalone_command(self):
        plan = subprocess.check_output(['make', '--no-print-directory', '-n', 'check-inventory'], cwd=ROOT, text=True)
        self.assertIn('tools/check_inventory.py', plan)
        for forbidden in ('setup_', 'cargo', 'cmake', 'test_runtime.py'):
            # These belong to later verification phases, never the lightweight declaration check.
            self.assertNotIn(forbidden, plan)
        result = subprocess.run([sys.executable, str(ROOT/'tools/check_inventory.py')], cwd=ROOT,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PASS verification inventory:', result.stdout)
