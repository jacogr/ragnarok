# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Cross-phase invariants for genuine deferred dependency waves and unresolved cycles."""
import unittest
import current_stf_dependency_waves_oracle as reference
from current_stf_oracle import decode_checkpoint
from current_stf_reporting_oracle import ready, pending
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as metadata_parse
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class CurrentStfDependencyWavesOracle(unittest.TestCase):
    """Independent E/Q and gas accounting determine the entire chain before native observations."""

    @classmethod
    def setUpClass(cls):
        """Retain independently calculated complete maps and priority/continuation traces once."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states = []
        for line in cls.lines:
            if line.startswith('P '): cls.states.append([decode_checkpoint(bytes.fromhex(line[2:]))])
            elif line.startswith('O '): cls.states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))

    def state(self, case, slot):
        """Every authored chain advances from slot1 through seven consecutive signed children."""
        return self.states[case][slot-1]

    def test_waiters_enter_from_actual_availability_without_execution(self):
        """A remains assigned while B, C and lookup-dependent D enter separate ready rows."""
        for case in range(5):
            for slot, name, dependencies in ((4, 'B', ['A']), (5, 'C', ['A', 'B']), (6, 'D', ['C'])):
                state = self.state(case, slot)
                self.assertEqual(pending(state[chapter_key(10)])[0]['guarantee']['report'][:32], reference.package('A'))
                row = ready(state[chapter_key(14)])[slot]
                self.assertEqual(len(row), 1); self.assertEqual(row[0][0][:32], reference.package(name))
                self.assertEqual(row[0][1], b''.join(sorted(reference.package(key) for key in dependencies)))
                self.assertEqual(state[chapter_key(15)], bytes(12))
                for sid in (42, 99): self.assertEqual(state[chapter_service(255, sid)], self.states[case][0][chapter_service(255, sid)])

    def test_four_priority_waves_and_two_affordable_batches(self):
        """One immediate report unlocks four topological waves; three declared limits fit the first budget exactly."""
        keys = {name: reference.package(name).hex() for name in 'ABCDE'}
        for case in range(5):
            trace = self.evidence['plans'][case][5] # Child slot7 releases A and E.
            self.assertEqual(trace['waves'], [[keys[name]] for name in 'BCDE'])
            self.assertEqual(trace['prefixes'], [[keys[name] for name in 'ABC'], [keys[name] for name in 'DE']])
            self.assertEqual(self.state(case, 7)[chapter_key(14)], bytes(12))
            packages = reference.pipeline.accumulated(self.state(case, 7)[chapter_key(15)])
            self.assertEqual(packages[:-1], [b'']*11)
            self.assertEqual(packages[-1], b''.join(sorted(reference.package(name) for name in 'ABCDE')))

    def test_actual_gas_and_repeated_guest_effects(self):
        """Continuation charges service99 a second time, retaining only its literal terminal implications."""
        for case, mode in enumerate(reference.pipeline.MODES):
            state = self.state(case, 7)
            parsed, _ = statistics_parse(state[chapter_key(13)], DEFAULT)
            services = {row[0]: row for row in parsed[3]}
            gas = reference.pipeline.guest_gas(mode)
            self.assertEqual(services[42][9:], (1, 0, 22))
            self.assertEqual(services[99][9:], (4, 0, 2*gas))
            self.assertEqual(self.evidence['plans'][case][5]['remaining_gas'], 300000-22-2*gas)
            expected = b'\0' if mode == 'panic-rollback' else b'\1'+(99).to_bytes(4, 'little')+reference.pipeline.COMMITMENT
            self.assertEqual(state[chapter_key(16)], expected)
            for sid in (42, 99): self.assertEqual(metadata_parse(state[chapter_service(255, sid)], 105)[2][2], 7)
            self.assertEqual(self.state(case, 8)[chapter_key(16)], b'\0')
            self.assertEqual(reference.pipeline.accumulated(self.state(case, 8)[chapter_key(15)])[-2], reference.pipeline.accumulated(state[chapter_key(15)])[-1])

    def test_lookup_union_is_canonical_and_duplicate_free(self):
        """E names B in both dependency families, while D relies exclusively on C's exact segment-root lookup."""
        parent = reference.pipeline.original('create'); reports = {}
        for slot in range(2, 7):
            gs, ass = reference.inputs(parent, reference.pipeline.original('create'), slot, False, reports)
            projection = reference.plan(parent, 'create', slot, ass, reports)
            _, parent = reference.pipeline.advance(parent, reference.pipeline.original('create'), 'create', slot, gs, ass, plan=projection)
        d, e = reports[reference.package('D')], reports[reference.package('E')]
        self.assertEqual(d['prerequisites'], b'')
        self.assertEqual(d['lookup'], reference.package('C')+reference.digest(reference.package('C')+b'exports'))
        dependencies = set(reference.chunks(e['prerequisites'], 32))|{pair[:32] for pair in reference.chunks(e['lookup'], 64)}
        self.assertEqual(dependencies, {reference.package('B'), reference.package('D')})

    def test_honestly_admitted_cycles_stop_without_false_progress(self):
        """Mutual same-block prerequisites remain available/queued, never becoming guests, outputs or processed history."""
        for case in (5, 6):
            for slot in range(4, 9):
                state = self.state(case, slot)
                rows = ready(state[chapter_key(14)])
                self.assertEqual(len(rows[4]), 2)
                self.assertEqual([(wire[:32], deps) for wire, deps in rows[4]], [(reference.package('A'), reference.package('B')), (reference.package('B'), reference.package('A'))])
                self.assertEqual(state[chapter_key(10)], bytes(2))
                self.assertEqual(state[chapter_key(15)], bytes(12)); self.assertEqual(state[chapter_key(16)], b'\0')
                self.assertEqual(self.evidence['plans'][case][slot-2]['waves'], [])
                self.assertEqual(self.evidence['plans'][case][slot-2]['prefixes'], [])
                for sid in (42, 99): self.assertEqual(state[chapter_service(255, sid)], self.states[case][0][chapter_service(255, sid)])
        self.assertEqual((self.evidence['transitions'], self.evidence['processed_reports'], self.evidence['guest_executions']), (49, 25, 15))
