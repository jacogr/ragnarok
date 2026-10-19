# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject inventory integration mistakes before native provisioning or execution.

Exposes InventoryPreflight for unittest discovery; test methods exercise the stated contracts.
"""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from runtime_provenance import validate_coverage, discover_project_sources, runtime_sources
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

    # Discovery schedules every validated family once, including additions without a runner edit.
    def test_discovered_failure_scheduling(self):
        from unittest.mock import patch
        from failure_checks import run_failure_suites
        families = {'first': {}, 'new_family': {}, 'second': {}}
        with patch('failure_checks.FAILURE_SUITES', families), patch('failure_checks.run_failure_suite') as run:
            run_failure_suites(None, {}, {}, None, None)
        self.assertEqual([call.args[-1] for call in run.call_args_list], list(families))
        with tempfile.TemporaryDirectory() as temporary, self.assertRaisesRegex(ValueError, 'No failure suites'):
            load_suites(Path(temporary))

    # Nested new helpers and JSON metadata must be covered; stale exclusions cannot hide deletions.
    def test_provenance_omissions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            paths = [root/name for name in ('Makefile', 'tools/helper.py', 'tools/nested/profile.json', 'tests/nested/oracle.py',
                                               'src/telemetry/client.nim', 'native/bridge.c', 'tests/fixtures/sample.bin')]
            for path in paths:
                # Files need no executable content for source coverage validation.
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            validate_coverage(root, paths, {})
            for omitted in paths:
                # Each scope is checked independently rather than only the tools directory.
                with self.subTest(path=omitted), self.assertRaisesRegex(ValueError, 'Unlisted runtime provenance'):
                    validate_coverage(root, [p for p in paths if p != omitted], {})
            excluded = 'tools/helper.py'
            validate_coverage(root, [p for p in paths if p != root/excluded],
                              {excluded: 'Historical standalone control.'})
            for exclusions in ({excluded: ''}, {'tools/deleted.py': 'Removed'}, {excluded: 'Already covered'}):
                # Exceptions must be current, justified and disjoint from actual report coverage.
                with self.subTest(exclusions=exclusions), self.assertRaisesRegex(ValueError, 'Invalid provenance exclusion'):
                    validate_coverage(root, paths, exclusions)

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

    # Runtime evidence uses deterministic unique discovery, including every current native requirement.
    def test_source_and_profile_discovery(self):
        sources = runtime_sources()
        self.assertEqual(sources, sorted(set(sources)))
        expected = set((ROOT/'tools/native_requirements').glob('*/*.json'))
        expected.update((ROOT/'src/telemetry').glob('*.nim'))
        self.assertTrue(expected)
        self.assertTrue(expected <= set(sources))

    # New inputs are discovered without shared manifest edits; generated and vendor trees stay bounded.
    def test_new_inputs_and_generated_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            names = ('Makefile', '.github/workflows/extra.yaml', 'src/telemetry/new.nim',
                     'native/bridge.h', 'native/extra/src/lib.rs', 'native/extra/Cargo.lock',
                     'spec/extra-pins.json', 'tools/nested/helper.py', 'tools/nested/profile.json',
                     'tools/new-requirements.txt', 'tests/support/helper.nim', 'tests/nested/oracle.py',
                     'tests/unit/state/test_new.output', 'tests/fixtures/new.bin',
                     'tests/fixtures/new.LICENSE', 'src/ui/static/nested/asset.bin', 'vectors/new.json')
            ignored = ('build/ui/generated.js', 'build/result.json', 'vendor/dependency/helper.py', 'tools/__pycache__/cache.py',
                       'tools/.cache/record.json', 'native/extra/target/generated.rs',
                       'tests/fixtures/.DS_Store')
            for name in (*reversed(names), *ignored):
                # Use arbitrary extensions for fixture bytes and realistic suffixes for generated artifacts.
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            discovered = discover_project_sources(root)
            self.assertEqual(discovered, {root/name for name in names})
            validate_coverage(root, sorted(discovered), {})
            added = root/'src/telemetry/later.nim'
            added.touch()
            self.assertIn(added, discover_project_sources(root))
            with self.assertRaisesRegex(ValueError, 'Unlisted runtime provenance'):
                validate_coverage(root, sorted(discovered), {})

    # Absent local inputs, duplicate identities and paths outside the checkout cannot be evidence.
    def test_invalid_provenance_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)/'repo'
            root.mkdir()
            makefile = root/'Makefile'
            makefile.touch()
            with self.assertRaisesRegex(ValueError, 'Missing runtime provenance'):
                validate_coverage(root, [makefile, root/'tools/missing.py'], {})
            with self.assertRaisesRegex(ValueError, 'Duplicate runtime provenance'):
                validate_coverage(root, [makefile, makefile], {})
            outside = root.parent/'outside.py'
            outside.touch()
            for path in (outside, root/'..'/'outside.py'):
                # Both direct absolute escapes and parent-relative aliases are rejected.
                with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'Invalid runtime provenance'):
                    validate_coverage(root, [makefile, path], {})
            alias = root/'alias.py'
            alias.symlink_to(outside)
            with self.assertRaisesRegex(ValueError, 'Invalid runtime provenance'):
                validate_coverage(root, [makefile, alias], {})
            validate_coverage(root, [makefile, root/'vendor/pinned/not-provisioned.json'], {})
            linked_root = root.parent/'linked-repo'
            linked_root.symlink_to(root, target_is_directory=True)
            validate_coverage(linked_root, [linked_root/'Makefile'], {})
            makefile.unlink()
            with self.assertRaisesRegex(ValueError, 'Missing runtime provenance'):
                validate_coverage(root, [makefile], {})


# The typed declaration is the case owner; parsing must never silently omit an unsupported value.
class ProbeCaseDeclarations(unittest.TestCase):
    def test_declarations(self):
        """Read the bounded enum format and reject malformed or duplicate case identities."""
        from failure_plans import driver_modes
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)/'driver.nim'
            header = '# @@ProbeCases\ntype VerificationProbe = enum\n'
            source.write_text(header+'  vpFirst = "first"\n  vpSecond = "second"\n\n')
            self.assertEqual(driver_modes(source), ('first', 'second'))
            for body in ('', '  vpFirst = "same"\n  vpSecond = "same"',
                         '  vpSame = "first"\n  vpSame = "second"',
                         '  vpBad = computedValue', '  vpSecond = "second"\n  vpFirst = "first"'):
                # Unsupported syntax and order cannot change the scheduled workload unnoticed.
                source.write_text(header+body+'\n\n')
                with self.subTest(body=body), self.assertRaises(ValueError):
                    driver_modes(source)
