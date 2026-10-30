# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject partial/tampered paired DOOM measurements and unintended CI execution."""
import copy
import unittest
from unittest.mock import patch
import pvm_doom_compare as compare
from pvm_doom_attribution import timing_samples


def complete_runs():
    """Author parser-compatible records with separate known candidate, baseline, reference and controls."""
    result = []
    for phase in ('init', 'tick'):
        for group, roles in enumerate(compare.GROUPS):
            for order in (0, 1):
                for role in (roles if order == 0 else roles[::-1]):
                    engine = 'reference' if role == 'reference' else 'native'
                    cpu = {'baseline': 1000, 'candidate': 900, 'reference': 250,
                           'control-a': 900, 'control-b': 900}[role]
                    output = '\n'.join(f'DOOM_SAMPLE,{engine},{phase},{i},{cpu},{cpu+1}'
                                       for i in range(13))+'\n'
                    output += f'DOOM_OK,{engine},{phase},1024005\n'
                    result.append(dict(phase=phase, group=group, order=order, role=role,
                        stdout=output, samples=timing_samples(output, engine, phase, 1024005),
                        output_bytes=1024005))
    return result


class DoomCompareTests(unittest.TestCase):
    def test_complete_cpu_ratios_and_controls(self):
        """Both reversed orders retain independently known CPU changes and zero same-image noise."""
        rows = compare.summarize(complete_runs())
        self.assertEqual(len(rows), 4)
        for row in rows:
            self.assertAlmostEqual(row['change_percent'], -10)
            self.assertEqual(row['control_percent'], 0)
            self.assertEqual(row['baseline_over_reference'], 4)
            self.assertEqual(row['candidate_over_reference'], 3.6)

    def test_refuse_partial_reordered_or_changed_samples(self):
        """Copied aggregates never replace complete strictly framed process output."""
        runs = complete_runs()
        cases = [runs[:-1], runs[::-1]]
        changed = copy.deepcopy(runs); changed[0]['samples'][3]['cpu_ns'] = 1; cases.append(changed)
        changed = copy.deepcopy(runs); changed[0]['order'] = False; cases.append(changed)
        changed = copy.deepcopy(runs); changed[0]['stdout'] += 'extra\n'; cases.append(changed)
        for bad in cases:
            with self.subTest(records=len(bad)), self.assertRaises(ValueError):
                compare.summarize(bad)

    def test_local_timings_refuse_before_build_or_preparation(self):
        """The timing entry rejects local runs before reading files or launching a compiler."""
        with patch.dict('os.environ', {'GITHUB_ACTIONS': 'false'}), self.assertRaises(RuntimeError):
            compare.run('HEAD')

    def test_source_snapshot_rejects_foreign_tree_and_missing_codec(self):
        """A revision cannot redirect imports through a symlink or omit the shared codec."""
        for tree in (b'120000 blob dead\tsrc/pvm/machine.nim\0',
                     b'100644 blob dead\tsrc/pvm/machine.nim\0'):
            with patch.object(compare, 'git', side_effect=[tree, b'owned']), self.assertRaises(ValueError):
                compare.endpoint('head', {})

    def test_revision_experiment_is_not_a_ci_job(self):
        """Historical comparison remains a Make tool rather than an extra skipped CI check."""
        text=(compare.ROOT/'.github/workflows/ci.yml').read_text()
        self.assertNotIn('  compare-doom:\n',text)
        self.assertIn('tools/pvm_doom_compare.py',(compare.ROOT/'Makefile').read_text())
