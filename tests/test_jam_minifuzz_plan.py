# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Metadata-only reference discovery rejects partial job builders before any target or native oracle runs."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import jam_minifuzz_plan as plan


class ReferencePlanContracts(unittest.TestCase):
    """Use a small pinned fixture and lazy synthetic builder to isolate coverage and ownership contracts."""

    def test_lazy_registration_and_independent_job_budgets(self):
        """Registering metadata does no work; missing steps or control bindings fail before process startup."""
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)/'reference.json'
            target.write_text(json.dumps(dict(chains=2,transitions=3,expected_sha256='1'*64)))
            pin = hashlib.sha256(target.read_bytes()).hexdigest()
            contract = ('TEST_REFERENCE',target,[(target,pin)])
            calls = [];selected = [dict(steps=[dict(kind='B'),dict(kind='B')]),dict(steps=[dict(kind='B')])]
            with patch.dict(plan.FIXTURE_CONTRACTS, example_reference=contract), patch.dict(plan._REFERENCES,{},clear=True):
                @plan.reference()
                def example_reference(identity):
                    """Return independent synthetic metadata only; no wire or application assertion is delegated here."""
                    calls.append(identity)
                    return selected,dict(reference=identity,fixture_sha256=pin,expected_sha256='1'*64,sessions=2,signed_imports=3,accepted_imports=3,refused_imports=0)
                self.assertEqual(calls,[])
                self.assertEqual(plan.expectations()[0]['exchanges'],14)
                self.assertEqual(calls,[])
                jobs,evidence = plan.prepare()
                self.assertEqual((len(jobs),evidence['signed_imports']),(2,3))
                selected[0]['steps'].pop()
                with self.assertRaises(AssertionError): plan.prepare()
                selected[0]['steps'].append(dict(kind='B'))
                # Control requirements are separately declared, so omitting the job binding cannot lower expectations.
                plan._REFERENCES['example_reference'] = plan.Reference(example_reference,lambda:dict(local_missing_evidence=1))
                with self.assertRaises(AssertionError): plan.prepare()
                target.write_text('{}')
                with self.assertRaises(AssertionError): plan.expectations()

    def test_refused_steps_cannot_be_replaced_by_success(self):
        """Keeping the total step count and a forged proof cannot hide a deleted refusal or invalid frozen budget."""
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)/'reference.json'
            selected = [dict(steps=[dict(kind='B'),dict(kind='R')])]
            def install(accepted=1, refused=1):
                """Freeze independently declared outcome budgets before installing a synthetic builder."""
                target.write_text(json.dumps(dict(chains=1,transitions=2,accepted=accepted,refused=refused,expected_sha256='1'*64)))
                return ('TEST_REFERENCE',target,[(target,hashlib.sha256(target.read_bytes()).hexdigest())])
            with patch.dict(plan.FIXTURE_CONTRACTS,example_reference=install()), patch.dict(plan._REFERENCES,{},clear=True):
                @plan.reference()
                def example_reference(identity):
                    """Retain the original proof so replacing R with B cannot repair evidence after mutation."""
                    return selected,dict(reference=identity,fixture_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                                         expected_sha256='1'*64,sessions=1,signed_imports=2,accepted_imports=1,refused_imports=1)
                jobs,evidence = plan.prepare()
                self.assertEqual((evidence['accepted_imports'],evidence['refused_imports']),(1,1))
                selected[0]['steps'][1]['kind'] = 'B'
                with self.assertRaises(AssertionError): plan.prepare()
                # Invalid and boolean counts cannot become a smaller independently declared campaign.
                for accepted,refused in ((2,1),(3,-1),(True,1),(1,False)):
                    plan.FIXTURE_CONTRACTS['example_reference'] = install(accepted,refused)
                    with self.assertRaises(AssertionError): plan.expectations()

    def test_all_source_owners_have_pinned_metadata(self):
        """Every declared fixture owner supplies positive immutable budgets without running its builder."""
        rows = plan.expectations()
        self.assertEqual([row['reference'] for row in rows],sorted(plan._REFERENCES))
        self.assertEqual(len({row['reference'] for row in rows}),len(rows))
        self.assertTrue(all(row['sessions'] > 0 and row['signed_imports'] > 0 for row in rows))
        self.assertTrue(all(len(row['fixture_sha256']) == 64 for row in rows))
