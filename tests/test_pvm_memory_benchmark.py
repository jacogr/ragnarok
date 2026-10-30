# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect complete native host-range observations and failure-safe downloadable artifacts."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from harness_fixtures import make_plan
from unittest.mock import patch
import pvm_memory_benchmark as benchmark
from dependencies import ROOT


def output(reverse=False):
    """Synthetic clocks exercise evidence framing without claiming measured native execution."""
    cases=tuple(reversed(benchmark.CASES)) if reverse else benchmark.CASES
    return '\n'.join(f'RANGE,{kind},{size},{sample},{10000+sample},{9000+sample}' for kind,size in cases for sample in range(13))


def report():
    """Own every fixed case in both process orders, with all warmup and measured observations."""
    return dict(status='checks-passed',passes=[dict(pass_index=p,samples=benchmark.parse_output(output(bool(p)),bool(p))) for p in range(2)])


class MemoryBenchmarkTests(unittest.TestCase):
    """Missing/corrupt output or failed reruns cannot retain a successful host API comparison."""

    def test_complete_reversed_processes(self):
        """Retain both clocks and every sample in the actual native process order."""
        for reverse in (False,True):
            rows=benchmark.parse_output(output(reverse),reverse)
            self.assertEqual(len(rows),len(benchmark.CASES)*13);self.assertEqual(rows[-1]['sample'],12)
            self.assertEqual((rows[0]['wall_ns'],rows[0]['cpu_ns']),(10000,9000))
        with self.assertRaises(ValueError):benchmark.parse_output(output(True))

    def test_invalid_observations(self):
        """Truncation, duplicates, case substitution, clock corruption and stray logs fail strictly."""
        good=output();lines=good.splitlines()
        for bad in ('','\n'.join(lines[:-1]),good+'\n'+lines[0], '\n'.join(reversed(lines)),
                    good.replace('read,512','write,512',1),good.replace(',10000,9000',',0,9000',1),
                    good.replace(',10000,9000',',10000,-1',1),good.replace(',10000,9000',',01,9000',1),
                    good.replace(',10000,9000',',10000,9223372036854775808',1),good+'\nwarning',good.replace('capture,4096','capture,512',1),good.replace('image,4096','capture,4096',1),good.replace('reserve,131072','clear,131072',1),
                    good.replace('clear,131072','clear,65536',1)):
            with self.subTest(tail=bad[-50:]),self.assertRaises(ValueError):benchmark.parse_output(bad)

    def test_incomplete_passes(self):
        """A full per-case sample set is still incomplete without both reversed-order passes."""
        data=report();self.assertIn('not PVM guest execution',benchmark.summarize(data))
        for passes in ([],data['passes'][:1],data['passes']+[data['passes'][0]]):
            with self.assertRaises(ValueError):benchmark.summarize(dict(status='checks-passed',passes=passes))
        broken=report();broken['passes'][0]['samples'].pop()
        with self.assertRaises(ValueError):benchmark.summarize(broken)

    def test_warmups_and_noise(self):
        """Only summary medians exclude warmups; slow measured passes remain visible and flagged."""
        data=report();before=benchmark.summarize(data)
        for p in data['passes']:
            for row in p['samples']:
                if row['sample']<3:row['cpu_ns']=10**12
        self.assertEqual(benchmark.summarize(data),before)
        for row in data['passes'][0]['samples']:row['cpu_ns']*=3
        snapshot=deepcopy(data)
        self.assertIn('noisy; inspect samples',benchmark.summarize(data));self.assertEqual(data,snapshot)

    def test_failed_rerun_clears_stale_samples(self):
        """Provisioning failures replace prior successes without starting native work."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            for name in ('results.json','summary.md','samples.csv'):(folder/name).write_text('old success')
            with patch.object(benchmark,'BUILD',folder),patch.object(benchmark,'installed',side_effect=RuntimeError('bad compiler')):
                with self.assertRaisesRegex(RuntimeError,'bad compiler'):benchmark.run()
            self.assertFalse((folder/'samples.csv').exists())
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')
            self.assertNotIn('| Operation |',(folder/'summary.md').read_text())

    def test_make_owned_opt_in(self):
        """Host API timings remain separate from normal verification and backend benchmark selection."""
        self.assertIn('tools/pvm_memory_benchmark.py',make_plan('bench-pvm-memory', skip=('setup',)))
        self.assertNotIn('tools/pvm_memory_benchmark.py',make_plan('check'))
