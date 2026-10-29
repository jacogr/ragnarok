# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Guard declarative native profiles and independent feature fixture preparation.

Exposes NativeRequirementsHarness for unittest discovery; test methods exercise the stated
contracts.
"""
from contextlib import ExitStack
from copy import deepcopy
from pathlib import Path
import sys
import json
import unittest
from unittest.mock import patch
from harness_fixtures import temporary_folder

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from native_requirements import NATIVE_REQUIREMENTS, validate_requirements, load_requirements
import native_fixtures


# A malformed manifest must fail preflight rather than silently dropping native checks.
class NativeRequirementsHarness(unittest.TestCase):
    # Missing and unexpected profiles both violate directory-discovered suite coverage.
    def test_coverage(self):
        for name in ('natural', 'unexpected'):
            # Exercise both an omitted suite and an unscheduled addition.
            records = deepcopy(NATIVE_REQUIREMENTS)
            records.pop(name) if name in records else records.update({name: records['natural']})
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'exactly'):
                validate_requirements(records)

    # Invalid schema, flags, profiles and batch membership cannot become executable arguments.
    def test_invalid_requirements(self):
        changes = [('unknown', True), ('prepared', 1), ('directory', '../outside'),
                   ('directory', 'codec'), ('directory', 'crypto'), ('libraries', []), ('libraries', 'observer'),
                   ('includes', []), ('includes', ['crypto', 'crypto']),
                   ('observers', ['injected']), ('defines', ['unchecked']),
                   ('observers', ['verify']), ('fixtures', 'state_report'),
                   ('fixtures', ['missing']), ('fixtures', ['state_report', 'state_report']),
                   ('fixtures', [None]), ('fixtures', [[]])]
        for field, value in changes:
            # The observer-only profile cannot use Rust call-site renaming without its library.
            records = deepcopy(NATIVE_REQUIREMENTS)
            records['state_layout'][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate_requirements(records)

    def test_fixed_heap_cap_retains_strict_define_allowlist(self):
        """Only the explicit one-MiB native test cap is admitted; arbitrary values remain rejected."""
        records = deepcopy(NATIVE_REQUIREMENTS)
        records['state_layout']['defines'] = ['nimMaxHeap=1']
        validate_requirements(records)
        for value in ('nimMaxHeap=0', 'nimMaxHeap=128', 'nimHardenOutOfMem', 'danger'):
            # None of these switches belongs to the selected hard-cap regression profile.
            records['state_layout']['defines'] = [value]
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_requirements(records)

    def test_explicit_jit_profiles_keep_headers_and_refusal_paired(self):
        """Both fixed JIT profiles require their own selector/header; arbitrary and mixed flags still fail."""
        for profile in ('pvmArm64Jit', 'pvmX86Jit'):
            for refused in (False, True):
                # A declared positive/refused profile may share mechanics, never a different native backend.
                records = deepcopy(NATIVE_REQUIREMENTS)
                records['pvm_runtime_policy'].update(
                    defines=[profile, *([profile+'Refuse'] if refused else [])], includes=['pvm_jit'])
                validate_requirements(records)
            for defines, includes in [([profile], []), ([profile+'Refuse'], ['pvm_jit']),
                                      ([profile+'Refuse'], []), ([], ['pvm_jit']),
                                      (['pvmArm64Jit', 'pvmX86Jit'], ['pvm_jit']),
                                      ([profile, 'pvmUnknownJit'], ['pvm_jit'])]:
                # Refusal without its selected backend, missing headers and arbitrary flags remain invalid.
                records = deepcopy(NATIVE_REQUIREMENTS)
                records['pvm_runtime_policy'].update(defines=defines, includes=includes)
                with self.subTest(defines=defines, includes=includes), self.assertRaises(ValueError):
                    validate_requirements(records)

    # OS redirection needs both its own object and header and cannot reuse a crypto/Rust observer profile.
    def test_storage_io_observer_requires_provider(self):
        for libraries, includes in [(['crypto'], ['crypto']), (['crypto', 'storage_io'], ['crypto'])]:
            records=deepcopy(NATIVE_REQUIREMENTS)
            records['state_layout'].update(observers=['io_fsync'],libraries=libraries,includes=includes)
            with self.subTest(libraries=libraries,includes=includes), self.assertRaises(ValueError):
                validate_requirements(records)

    # Write isolated profiles with the actual suite contract, without invoking native setup.
    def profiles(self, folder):
        for name, record in NATIVE_REQUIREMENTS.items():
            # Source-family ownership and alphabetical fields mirror the checked-in file layout.
            path = folder/record['directory']/(name+'.json')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(record, sort_keys=True))

    # Splitting metadata changes no linking, flags, fixtures or inventory coverage.
    def test_split_profiles(self):
        with temporary_folder() as folder:
            self.profiles(folder)
            self.assertEqual(load_requirements(folder), NATIVE_REQUIREMENTS)
            (folder/'codec/natural.json').unlink()
            with self.assertRaisesRegex(ValueError, 'exactly'):
                load_requirements(folder)

    # Duplicate keys and duplicate suite identities must never overwrite a previously validated profile.
    def test_duplicate_profiles(self):
        with temporary_folder() as folder:
            self.profiles(folder)
            duplicate = dict(NATIVE_REQUIREMENTS['natural'], directory='state')
            (folder/'state/natural.json').write_text(json.dumps(duplicate, sort_keys=True))
            with self.assertRaisesRegex(ValueError, 'duplicate native'):
                load_requirements(folder)
            (folder/'state/natural.json').unlink()
            (folder/'codec/natural.json').write_text('{"directory":"codec","directory":"codec"}')
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                load_requirements(folder)

    # Module ownership, filename identity and field order are enforced before any test is executed.
    def test_profile_ownership(self):
        scenarios = ('root', 'nested', 'wrong-directory', 'bad-name', 'field-order')
        for scenario in scenarios:
            with self.subTest(scenario=scenario), temporary_folder() as folder:
                self.profiles(folder)
                record = NATIVE_REQUIREMENTS['natural']
                path = folder/'codec/natural.json'
                if scenario == 'root':
                    path = folder/'unexpected.json'  # Profiles must belong to one source family.
                elif scenario == 'nested':
                    path = folder/'codec/nested/natural.json'  # Extra nesting hides ownership.
                elif scenario == 'wrong-directory':
                    path = folder/'state/misplaced.json'  # Metadata still declares codec.
                elif scenario == 'bad-name':
                    path = folder/'codec/Bad-Name.json'  # Suite identities have stable lowercase prefixes.
                else:
                    record = dict(reversed(list(record.items())))  # Unordered independent fields are refused.
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(record))
                with self.assertRaises(ValueError):
                    load_requirements(folder)

    # Existing report consumers retain the exact nesting and preparation sequence across features.
    def test_aggregate_evidence(self):
        order = []
        names = ('schedule', 'markers', 'authentication', 'transition', 'commitment',
                 'preimage_transition', 'accumulation_credit', 'accumulation_context', 'accumulation_invocation', 'accumulation_service', 'accumulation_round', 'accumulation_inputs', 'accumulation_operands', 'accumulation_queue', 'admission', 'disputes', 'availability', 'guarantors', 'guarantee_credentials', 'report_policy', 'report_anchors', 'report_packages', 'report_assignments')
        plan = native_fixtures.PROVIDERS.plan('sealer')
        with ExitStack() as stack:
            for provider in plan:
                # Include newly declared features automatically while retaining historical relative-order checks.
                def prepare(folder, name=provider.name):
                    order.append(name)
                    return {name: ('fixture', folder, ())}, {'fixture_sha256': name}
                stack.enter_context(patch.object(native_fixtures, provider.function, side_effect=prepare))
            fixtures, evidence = native_fixtures.unit_sealer_fixture(Path('/fixture'))
        self.assertEqual([name for name in order if name in names], list(names))
        self.assertEqual(list(fixtures), order)
        self.assertEqual(list(evidence), ['fixture_sha256', *reversed(order[1:])])
        self.assertEqual(evidence, {'fixture_sha256': 'schedule',
                                   **{name: {'fixture_sha256': name} for name in order[1:]}})

    # Feature entry points call only their own independent oracle and retain its exact bytes/hash.
    def test_feature_isolation(self):
        with temporary_folder() as folder:
            path = folder/'disputes.bin'
            evidence = {'fixture_sha256': 'independent-hash'}
            with patch('disputes_transition_fixtures.prepare', return_value=(path, evidence)) as prepare:
                with patch('availability_transition_fixtures.prepare', side_effect=AssertionError('unrelated preparation')):
                    fixtures, observed = native_fixtures.unit_disputes_fixture(folder)
            prepare.assert_called_once_with(folder)
            self.assertEqual(fixtures, {'disputes_transition': (
                'RAGNAROK_DISPUTES_TRANSITION', path, ((path, 'independent-hash'),))})
            self.assertIs(observed, evidence)


# Direct execution uses the same tests as Python discovery.
if __name__ == '__main__':
    unittest.main()
