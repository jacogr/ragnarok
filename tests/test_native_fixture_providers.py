# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Guard source-owned generated-fixture declarations, consumer binding and preparation plans.

Exposes NativeFixtureProvidersHarness for Python discovery; no native tools execute here.
"""
from copy import deepcopy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from native_fixture_providers import FixtureProviders
import native_fixtures
import native_preparation
import native_requirements


# New providers and consumers must work without shared registration lists or weaker fresh-input checks.
class NativeFixtureProvidersHarness(unittest.TestCase):
    # Create a named inert callable without running it during provider registration.
    def function(self, name='example', result=None):
        """Return a test-only provider with a stable identity and caller-supplied result."""
        def prepare(folder):
            return result
        prepare.__name__ = 'unit_'+name+'_fixture'
        return prepare

    # A new provider and suite execute in selected and full plans using only their local declarations.
    def test_new_provider_and_consumer(self):
        providers = FixtureProviders()
        contract = ('RAGNAROK_EXAMPLE', Path('/fixture/input'), ())
        function = providers.fixture(group='root', order=10, evidence=('example_fixture', 'example-log'))(
            self.function(result=({'default': contract}, {'independent': True})))
        requirements = {'new_suite': {'prepared': True, 'provider': 'example'}}
        recorded = []
        with patch.object(sys.modules[__name__], function.__name__, function, create=True), patch.dict(
                native_requirements.NATIVE_REQUIREMENTS, requirements, clear=True), patch.object(
                native_preparation, 'PROVIDERS', providers), patch.object(
                native_preparation, 'unit_runtime_fixtures', return_value={}):
            selected, observed = native_preparation.prepare_selected_fixture(Path('/fixture'), 'new_suite')
            full, evidence = native_preparation.prepare_unit_fixtures(
                Path('/fixture'), None, None, None,
                record=lambda key, value: recorded.append((key, value)))
        self.assertEqual(selected, {'new_suite': contract})
        self.assertEqual(full, selected)
        self.assertEqual(observed, {'independent': True})
        self.assertEqual(evidence, {'example_fixture': observed})
        self.assertEqual(recorded, [('example_fixture', observed)])
        self.assertEqual(providers.evidence_files(), {'example_fixture': 'example-log'})

    # Variants express different input contracts while sibling consumer names remain solely in requirements.
    def test_variant_binding(self):
        providers = FixtureProviders()
        function = providers.fixture(group='sealer', order=10, variants=('default', 'report'))(
            self.function(result=({'default': 'ordinary', 'report': 'with-report'}, {'sha': 'pin'})))
        requirements = {'one': {'provider': 'example'},
                        'two': {'provider': 'example', 'variant': 'report'},
                        'unrelated': {'prepared': False}}
        with patch.dict(native_requirements.NATIVE_REQUIREMENTS, requirements, clear=True):
            fixtures, _ = function(Path('/fixture'))
        self.assertEqual(fixtures, {'one': 'ordinary', 'two': 'with-report'})

    # Missing or unexpected raw variants cannot turn into incomplete successful generated manifests.
    def test_invalid_results(self):
        for result in ({}, {'unexpected': 'data'}, None):
            # The expected result shape comes from the provider declaration, never observed output.
            with self.subTest(result=result):
                providers = FixtureProviders()
                function = providers.fixture(group='sealer', order=10)(
                    self.function(result=(result, {})))
                with self.assertRaisesRegex(ValueError, 'provider result'):
                    function(Path('/fixture'))

    # Invalid metadata must fail at declaration time without executing a generator.
    def test_invalid_metadata(self):
        changes = [('group', 'unknown'), ('order', 0), ('order', True),
                   ('inputs', ('unknown',)), ('inputs', ([],)), ('inputs', ('certificates',)),
                   ('variants', ()), ('variants', ([],)), ('variants', ('default', 'default')),
                   ('variants', ('Bad-Variant',)), ('deferred', True), ('aggregate', True),
                   ('evidence', ('nested', 'file'))]
        for key, value in changes:
            # Every malformed declaration is isolated so one accepted case cannot hide behind another failure.
            with self.subTest(key=key, value=value):
                options = dict(group='sealer', order=10)
                options[key] = value
                with self.assertRaises(ValueError):
                    FixtureProviders().fixture(**options)
        for evidence in (None, ('one',), ('one', '../escape'), ('one', 1)):
            with self.subTest(evidence=evidence), self.assertRaises(ValueError):
                FixtureProviders().fixture(group='root', order=10, evidence=evidence)

    # Duplicate identities, execution ranks, report keys and filenames cannot overwrite earlier metadata.
    def test_duplicate_declarations(self):
        for duplicate in ('identity', 'order', 'report', 'filename'):
            # Use distinct defaults so each scenario proves its specific collision check.
            with self.subTest(duplicate=duplicate):
                providers = FixtureProviders()
                providers.fixture(group='root', order=10, evidence=('first', 'first-log'))(self.function('first'))
                name, order, evidence = 'second', 20, ('second', 'second-log')
                if duplicate == 'identity':
                    name = 'first'
                elif duplicate == 'order':
                    order = 10
                elif duplicate == 'report':
                    evidence = ('first', 'second-log')
                else:
                    evidence = ('second', 'first-log')
                with self.assertRaisesRegex(ValueError, 'Duplicate|duplicate'):
                    providers.fixture(group='root', order=order, evidence=evidence)(self.function(name))

    # Required runtime resources are checked before a provider can run or publish partial evidence.
    def test_missing_resources(self):
        providers = FixtureProviders()
        providers.fixture(group='runtime', order=10, inputs=('certificates',))(self.function())
        with self.assertRaisesRegex(ValueError, 'Missing native fixture provider input'):
            providers.providers['example'].prepare(Path('/fixture'))

    # Provider references, fresh-input flags and variants must agree during inventory preflight.
    def test_requirement_rejection(self):
        scenarios = ('missing', 'unknown', 'variant', 'unexpected', 'aggregate', 'type')
        for scenario in scenarios:
            # Mutate one existing complete profile while retaining independent discovered-suite coverage.
            with self.subTest(scenario=scenario):
                records = deepcopy(native_requirements.NATIVE_REQUIREMENTS)
                record = records['pvm_gas']
                if scenario == 'missing':
                    record.pop('provider')
                elif scenario == 'unknown':
                    record['provider'] = 'unknown'
                elif scenario == 'variant':
                    record['variant'] = 'unknown'
                elif scenario == 'unexpected':
                    record['prepared'] = False
                elif scenario == 'aggregate':
                    record['provider'] = 'sealer'
                else:
                    record['provider'] = []
                with self.assertRaisesRegex(ValueError, 'native fixture provider'):
                    native_requirements.validate_requirements(records)

    # Top-level report writes retain their historical order, including the deliberately deferred validator stage.
    def test_evidence_write_order(self):
        from contextlib import ExitStack
        recorded = []
        plan = native_preparation.PROVIDERS.plan('root')
        with ExitStack() as stack:
            stack.enter_context(patch.object(native_preparation, 'unit_runtime_fixtures', return_value={}))
            for provider in plan:
                # Distinct manifests catch duplicate/overwritten stages independently of the evidence keys.
                stack.enter_context(patch.object(native_fixtures, provider.function,
                    return_value=({provider.name: 'manifest'}, {'sha': provider.name})))
            _, evidence = native_preparation.prepare_unit_fixtures(Path('/fixture'), None, None, None,
                record=lambda key, value: recorded.append(key))
        historical = ['pvm_step_fixture', 'pvm_gas_fixture', 'store_replay_fixture',
            'authorization_stf_fixture', 'history_stf_fixture', 'signing_domain_fixture',
            'entropy_stf_fixture', 'validator_stf_fixture', 'ticket_stf_fixture', 'sealer_stf_fixture']
        self.assertEqual([key for key in evidence if key in historical], historical)
        self.assertEqual(recorded, [provider.evidence[0] for provider in plan if not provider.deferred]
                         +[provider.evidence[0] for provider in plan if provider.deferred])
        self.assertEqual([key for key in recorded if key in historical],
                         [*historical[:7], 'ticket_stf_fixture', 'sealer_stf_fixture', 'validator_stf_fixture'])

    # A later generator failure must preserve earlier completed-stage evidence and stop the plan immediately.
    def test_generator_failure(self):
        recorded = []
        with patch.object(native_preparation, 'unit_runtime_fixtures', return_value={}), patch.object(
                native_fixtures, 'unit_pvm_step_fixture', return_value=({'step': 'input'}, {'sha': 'step'})), patch.object(
                native_fixtures, 'unit_pvm_gas_fixture', side_effect=RuntimeError('generator failed')), patch.object(
                native_fixtures, 'unit_store_fixture') as store:
            with self.assertRaisesRegex(RuntimeError, 'generator failed'):
                native_preparation.prepare_unit_fixtures(Path('/fixture'), None, None, None,
                    record=lambda key, value: recorded.append((key, value)))
        self.assertEqual(recorded, [('pvm_step_fixture', {'sha': 'step'})])
        store.assert_not_called()


# Importing this module exposes regression checks without preparing fixtures or building native libraries.
if __name__ == '__main__':
    unittest.main()
