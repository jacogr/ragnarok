# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent precedence, scheduling and cohort invariants for privileged host operations across rotation."""
import unittest
import current_stf_rotation_privileges_oracle as reference
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account_parse


class RotationPrivilegesTests(unittest.TestCase):
    """Check cross-phase protocol relationships independently of native execution and frozen hashes."""

    @classmethod
    def setUpClass(cls):
        """Derive each whole chain once and retain states indexed by the actual slot."""
        cls.chains = {}
        for case in reference.cases():
            states = {1: case['initial']}
            for _, state, _ in case['steps']:
                states[int.from_bytes(state[chapter_key(11)], 'little')] = state
            cls.chains[case['name']] = states

    def test_manager_handoff_cannot_be_reclaimed(self):
        """Real authority changes survive growth/shrinkage and deny later attempts by the old manager."""
        for profile in reference.handoff.PROFILES:
            states = self.chains['manager-'+profile]
            selected = 42 if profile in ('handoff','checkpoint-panic','unauthorized') else 99
            for slot in (12,13,24,25):
                self.assertEqual(reference.host.privileges(states[slot][chapter_key(12)])[0],selected)

    def test_allowances_start_after_publication(self):
        """A newly granted budget cannot cause participation in its own publication block."""
        for profile in reference.bless.PROFILES:
            states = self.chains['allowances-'+profile]
            retained = profile not in ('panic','unauthorized')
            self.assertEqual(account_parse(states[12][chapter_service(255,42)],105)[2][2],0)
            self.assertEqual(account_parse(states[13][chapter_service(255,42)],105)[2][2],13 if retained else 0)
            self.assertEqual(account_parse(states[25][chapter_service(255,42)],105)[2][2],25 if retained else 0)

    def test_queue_handoff_and_denied_domains(self):
        """The first accepted assignment persists after later unauthorized calls and both epoch boundaries."""
        for profile in reference.assign.PROFILES[:-1]:
            states = self.chains['assignment-'+profile]
            retained = profile in ('assign','checkpoint-panic')
            for slot in (12,13,24,25):
                self.assertEqual(reference.host.privileges(states[slot][chapter_key(12)])[3][1],42 if retained else 99)
                queue = states[slot][chapter_key(2)][2560:5120]
                self.assertEqual(queue,reference.assign.queue() if retained else bytes(2560))
            self.assertEqual(states[25][chapter_key(2)][:2560]+states[25][chapter_key(2)][5120:],bytes(5120))

    def test_original_producer_and_manager_precedence(self):
        """Manager role redirection cannot substitute its own queue; unchanged proposals defer to the old owner."""
        for profile in reference.roles.PROFILES:
            states = self.chains['precedence-'+profile]
            first = reference.host.privileges(states[12][chapter_key(12)])[3][1]
            self.assertEqual(first,99 if profile in ('manager-keeps','manager-panic') else 0)
            self.assertEqual(states[12][chapter_key(2)][2560:5120],bytes(2560) if profile=='assigner-panic' else reference.assign.queue())
        keeps = self.chains['precedence-manager-keeps']
        self.assertEqual([reference.host.privileges(keeps[s][chapter_key(12)])[3][1] for s in (12,13,24,25)],[99,42,99,42])

    def test_actual_rosters_and_report_activity(self):
        """The complete chains retain current/previous6/9 dimensions and report-triggered participation after shrinkage."""
        for states in self.chains.values():
            for slot,counts in ((12,(9,6)),(24,(6,9)),(25,(6,9))):
                current,previous,cores,services = reference.host.statistics(states[slot])
                self.assertEqual((len(current),len(previous)),counts)
                self.assertEqual(cores[1][1],5 if slot in (12,25) else 7)
                self.assertEqual({row[0]:row for row in services}[99][9],1)


if __name__ == '__main__':
    unittest.main()
